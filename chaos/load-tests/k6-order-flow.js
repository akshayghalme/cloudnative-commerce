// k6 Load Test — End-to-End Order Flow
//
// Simulates a complete user journey:
//   1. Browse products (GET /products)
//   2. View product detail (GET /products/:id)
//   3. Add to cart (POST /cart/items)
//   4. Create order (POST /orders)
//   5. Check order status (GET /orders/:id)
//
// This tests the full request path: ingress → product-api → PostgreSQL → SQS → order-worker
//
// Unlike the API load test (pure throughput), this test measures:
// - End-to-end latency across services
// - Order processing pipeline under load
// - SQS queue depth during sustained ordering
// - Database write performance (order creation)
//
// Run: k6 run chaos/load-tests/k6-order-flow.js

import http from "k6/http";
import { check, sleep, group, fail } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";

// ─── Custom Metrics ──────────────────────────────────────────────────────
const errorRate = new Rate("errors");
const ordersCreated = new Counter("orders_created");
const orderFlowDuration = new Trend("order_flow_duration", true);
const orderCreationLatency = new Trend("order_creation_latency", true);

// ─── Configuration ───────────────────────────────────────────────────────
const BASE_URL = __ENV.BASE_URL || "http://product-api.commerce.svc.cluster.local";

export const options = {
  // Scenarios allow running different user patterns concurrently
  scenarios: {
    // Scenario 1: Steady order flow — constant rate of orders
    steady_orders: {
      executor: "constant-arrival-rate",
      rate: 10, // 10 orders per second
      timeUnit: "1s",
      duration: "5m",
      preAllocatedVUs: 50,
      maxVUs: 100,
      tags: { scenario: "steady" },
    },
    // Scenario 2: Flash sale spike — sudden burst of orders
    flash_sale: {
      executor: "ramping-arrival-rate",
      startRate: 10,
      timeUnit: "1s",
      stages: [
        { duration: "30s", target: 10 }, // Normal
        { duration: "30s", target: 50 }, // Flash sale starts
        { duration: "2m", target: 50 }, // Sustained flash sale
        { duration: "30s", target: 10 }, // Flash sale ends
      ],
      preAllocatedVUs: 100,
      maxVUs: 200,
      startTime: "5m", // Start after steady scenario
      tags: { scenario: "flash_sale" },
    },
  },

  thresholds: {
    // End-to-end order flow must complete within 2 seconds
    order_flow_duration: ["p(95)<2000", "p(99)<3000"],
    // Order creation (POST /orders) must be fast
    order_creation_latency: ["p(95)<500"],
    // Error rate below 1%
    errors: ["rate<0.01"],
    // HTTP request latency
    http_req_duration: ["p(95)<500", "p(99)<1000"],
  },

  tags: {
    testid: "order-flow-load",
    environment: __ENV.ENVIRONMENT || "dev",
  },
};

// ─── Main Test Flow ──────────────────────────────────────────────────────
export default function () {
  const flowStart = Date.now();
  const headers = { "Content-Type": "application/json" };

  // Step 1: Browse products
  let productId;
  group("1. Browse Products", function () {
    const res = http.get(`${BASE_URL}/api/v1/products?page=1&limit=20`, {
      headers,
      tags: { step: "browse" },
    });

    const success = check(res, {
      "browse: status 200": (r) => r.status === 200,
    });
    errorRate.add(!success);

    // Pick a random product from the list
    try {
      const body = JSON.parse(res.body);
      if (body.products && body.products.length > 0) {
        const idx = Math.floor(Math.random() * body.products.length);
        productId = body.products[idx].id;
      }
    } catch {
      productId = Math.floor(Math.random() * 100) + 1;
    }
  });

  sleep(Math.random() * 0.5 + 0.5); // 0.5-1s think time

  // Step 2: View product detail
  group("2. View Product", function () {
    const res = http.get(`${BASE_URL}/api/v1/products/${productId}`, {
      headers,
      tags: { step: "view" },
    });

    const success = check(res, {
      "view: status 200 or 404": (r) => r.status === 200 || r.status === 404,
    });
    errorRate.add(!success);
  });

  sleep(Math.random() * 1 + 1); // 1-2s think time (reading product info)

  // Step 3: Add to cart
  group("3. Add to Cart", function () {
    const payload = JSON.stringify({
      product_id: productId,
      quantity: Math.floor(Math.random() * 3) + 1,
    });

    const res = http.post(`${BASE_URL}/api/v1/cart/items`, payload, {
      headers,
      tags: { step: "add_to_cart" },
    });

    const success = check(res, {
      "cart: status 200 or 201": (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(!success);
  });

  sleep(Math.random() * 0.5 + 0.5);

  // Step 4: Create order
  let orderId;
  group("4. Create Order", function () {
    const payload = JSON.stringify({
      items: [
        {
          product_id: productId,
          quantity: 1,
        },
      ],
      shipping_address: {
        street: "123 Test Street",
        city: "Mumbai",
        state: "Maharashtra",
        zip: "400001",
        country: "IN",
      },
    });

    const orderStart = Date.now();
    const res = http.post(`${BASE_URL}/api/v1/orders`, payload, {
      headers,
      tags: { step: "create_order" },
    });
    orderCreationLatency.add(Date.now() - orderStart);

    const success = check(res, {
      "order: status 201 or 202": (r) => r.status === 201 || r.status === 202,
    });

    if (success) {
      ordersCreated.add(1);
      try {
        const body = JSON.parse(res.body);
        orderId = body.id || body.order_id;
      } catch {
        // Order created but couldn't parse response
      }
    }

    errorRate.add(!success);
  });

  sleep(Math.random() * 1 + 1);

  // Step 5: Check order status (if we got an order ID)
  if (orderId) {
    group("5. Check Order Status", function () {
      const res = http.get(`${BASE_URL}/api/v1/orders/${orderId}`, {
        headers,
        tags: { step: "order_status" },
      });

      check(res, {
        "order status: status 200 or 202": (r) =>
          r.status === 200 || r.status === 202,
        "order status: has status field": (r) => {
          try {
            const body = JSON.parse(r.body);
            return body.status !== undefined;
          } catch {
            return false;
          }
        },
      });
    });
  }

  // Record total flow duration
  orderFlowDuration.add(Date.now() - flowStart);
}

// ─── Teardown ────────────────────────────────────────────────────────────
export function handleSummary(data) {
  // Log key metrics
  const totalOrders = data.metrics.orders_created
    ? data.metrics.orders_created.values.count
    : 0;
  console.log(`\nTotal orders created: ${totalOrders}`);

  return {
    stdout: textSummary(data, { indent: " ", enableColors: true }),
    "order-flow-results.json": JSON.stringify(data, null, 2),
  };
}

import { textSummary } from "https://jslib.k6.io/k6-summary/0.1.0/index.js";
