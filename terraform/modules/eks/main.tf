# ─── Data Sources ─────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# TLS certificate for the OIDC provider — needed to establish trust between
# EKS and IAM so pods can assume IAM roles (IRSA).
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# ─── IAM Role — EKS Control Plane ────────────────────────────────────────────
# The control plane (API server, scheduler, controller manager) assumes this
# role to make AWS API calls on your behalf (create ENIs, describe instances, etc.)

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# Required for VPC resource controller — lets EKS manage security groups
# for load balancers and nodes.
resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# ─── Security Group — Control Plane ──────────────────────────────────────────
# EKS creates its own cluster security group automatically, but we create an
# additional one so we can attach custom rules (e.g. allow from bastion/CI).

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  # All outbound traffic allowed — control plane needs to reach AWS APIs,
  # pull ECR images, and talk to nodes.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

# Allow nodes to reach the control plane API server (port 443).
resource "aws_security_group_rule" "cluster_ingress_nodes_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Allow nodes to reach API server"
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name    = var.cluster_name
  version = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  # Send control plane logs to CloudWatch.
  # These are invaluable for debugging auth issues and scheduling failures.
  enabled_cluster_log_types = var.enable_cluster_log_types

  # Encrypt Kubernetes secrets at rest using AWS-managed KMS key.
  # Secrets (DB passwords, API keys stored as k8s Secrets) are encrypted
  # in etcd — without this, they're base64-encoded plaintext.
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = var.tags
}

# ─── KMS Key — Secrets Encryption ────────────────────────────────────────────

resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-secrets-key"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# ─── CloudWatch Log Group — Control Plane Logs ───────────────────────────────

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30

  tags = var.tags
}

# ─── OIDC Provider — IRSA ─────────────────────────────────────────────────────
# This is what enables pod-level IAM roles (IRSA — IAM Roles for Service Accounts).
#
# Without OIDC: all pods on a node share the node's IAM role — over-privileged.
# With OIDC: each pod gets its own IAM role, scoped to exactly what it needs.
#
# How it works:
#   1. EKS exposes an OIDC issuer URL
#   2. We register it as an Identity Provider in IAM
#   3. IAM roles can trust tokens from this provider
#   4. Pods annotated with an IAM role ARN get credentials injected
#      by the EKS Pod Identity Webhook

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-oidc-provider"
  })
}

# ─── IAM Role — Node Group ───────────────────────────────────────────────────
# EC2 nodes assume this role. It needs permissions to:
# - Join the EKS cluster (describe cluster)
# - Pull images from ECR
# - Send metrics/logs to CloudWatch (via vpc-cni and other add-ons)

resource "aws_iam_role" "nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEKS_CNI_Policy" {
  # vpc-cni needs to assign ENIs and IPs to pods.
  # Note: better practice is to use IRSA for vpc-cni (Task 14),
  # but node-level policy works for the initial cluster bootstrap.
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEC2ContainerRegistryReadOnly" {
  # Nodes need to pull images from ECR.
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
}

# ─── Security Group — Nodes ───────────────────────────────────────────────────

resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "EKS managed node group security group"
  vpc_id      = var.vpc_id

  # Node-to-node communication — pods need to talk to each other across nodes.
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow node-to-node communication"
  }

  # Control plane to nodes — API server calls kubelet on port 10250.
  ingress {
    from_port                = 1025
    to_port                  = 65535
    protocol                 = "tcp"
    security_group_id        = aws_security_group.cluster.id
    description              = "Allow control plane to reach node kubelet and services"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (ECR pulls, AWS APIs, external services)"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nodes-sg"
    # Karpenter uses this tag to discover the node security group
    "karpenter.sh/discovery" = var.cluster_name
  })
}

# Separate rule to break circular dependency between cluster SG and nodes SG
resource "aws_security_group_rule" "nodes_ingress_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Allow control plane to reach nodes on 443"
}

# ─── Managed Node Group ───────────────────────────────────────────────────────
# Managed node groups handle: AMI updates, node draining during upgrades,
# and replacement of unhealthy nodes. Much less operational overhead than
# self-managed node groups.

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-general"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids

  # Instance types — providing multiple enables AZ flexibility.
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Rolling update strategy — EKS drains nodes before terminating them.
  # max_unavailable = 1 means one node at a time is replaced.
  update_config {
    max_unavailable = 1
  }

  disk_size = var.node_disk_size_gb

  # Use AL2023 (Amazon Linux 2023) — replaces AL2, better security posture.
  ami_type = "AL2023_x86_64_STANDARD"

  # Labels applied to all nodes in this group.
  # Used by pod nodeSelector/nodeAffinity rules.
  labels = {
    role        = "general"
    environment = lookup(var.tags, "Environment", "dev")
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.nodes_AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-general-node"
  })

  lifecycle {
    # Ignore desired_size changes after creation — HPA and Karpenter manage this.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ─── EKS Add-ons ──────────────────────────────────────────────────────────────
# Managed add-ons are updated by AWS alongside cluster upgrades.
# Pinning to specific versions prevents surprise breaking changes.

# vpc-cni — assigns VPC IPs directly to pods (AWS VPC CNI plugin).
# This is what allows pods to have real VPC IPs and communicate natively.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "vpc-cni"
  addon_version            = "v1.18.1-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# kube-proxy — maintains network rules on nodes for Service routing.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "kube-proxy"
  addon_version            = "v1.30.0-eksbuild.3"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# coredns — cluster DNS resolution. Every Service gets a DNS name via CoreDNS.
resource "aws_eks_addon" "coredns" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "coredns"
  addon_version            = "v1.11.1-eksbuild.9"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS requires at least one node to be running before it can schedule.
  depends_on = [aws_eks_node_group.general]

  tags = var.tags
}

# aws-ebs-csi-driver — allows PersistentVolumeClaims to create EBS volumes.
# Required for StatefulSets (e.g. Prometheus, Loki with persistent storage).
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.30.0-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE"

  # EBS CSI driver needs IRSA to create/attach EBS volumes on your behalf.
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  depends_on = [
    aws_eks_node_group.general,
    aws_iam_openid_connect_provider.eks,
  ]

  tags = var.tags
}

# ─── IRSA — EBS CSI Driver ───────────────────────────────────────────────────
# The EBS CSI driver needs IAM permissions to create, attach, and delete EBS
# volumes. We use IRSA so only the CSI driver pod gets these permissions,
# not the entire node.

data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
