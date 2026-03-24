# ---- Build stage ----
FROM golang:1.22-alpine3.19 AS builder

WORKDIR /app

# Download dependencies first (cached layer — only re-runs if go.mod/go.sum change)
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# CGO disabled: produces a static binary with no libc dependency (required for distroless)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o product-api ./main.go

# ---- Run stage ----
# distroless has no shell, no package manager, no tools — minimal attack surface
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

COPY --from=builder /app/product-api .

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/app/product-api", "-healthcheck"]

USER nonroot:nonroot

ENTRYPOINT ["/app/product-api"]
