"""
Order Worker — SQS consumer for async order processing.

Message flow:
  storefront → SQS → worker → postgres (order record)
                            → SQS delete (ack)

On failure:
  - Message becomes visible again after VISIBILITY_TIMEOUT
  - SQS DLQ receives the message after maxReceiveCount retries
"""

import json
import signal
import sys
import time
from typing import Any

import boto3
import psycopg
import structlog

from config import Config

log = structlog.get_logger()


def configure_logging(env: str) -> None:
    structlog.configure(
        processors=[
            structlog.stdlib.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.BoundLogger,
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
    )


class OrderWorker:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.sqs = boto3.client("sqs", region_name=cfg.AWS_REGION)
        self.db_conn: psycopg.Connection | None = None
        self._running = True

        # Register SIGTERM/SIGINT handlers for graceful shutdown.
        # Kubernetes sends SIGTERM before killing the pod — we finish
        # the current batch then exit cleanly.
        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)

    def _handle_shutdown(self, signum: int, frame: Any) -> None:
        log.info("shutdown signal received, draining current batch", signal=signum)
        self._running = False

    def connect_db(self) -> None:
        self.db_conn = psycopg.connect(self.cfg.DATABASE_URL)
        log.info("connected to postgres")

    def process_message(self, body: dict) -> None:
        """
        Process a single order message.
        Runs inside a transaction — if anything raises, the transaction
        rolls back and the message stays in SQS for retry.
        """
        order_id = body["order_id"]
        user_id = body["user_id"]
        items = body["items"]  # [{"product_id": ..., "quantity": ...}]

        with self.db_conn.transaction():
            # Idempotency: skip if already processed (duplicate delivery is normal in SQS)
            with self.db_conn.cursor() as cur:
                cur.execute(
                    "SELECT id FROM orders WHERE id = %s", (order_id,)
                )
                if cur.fetchone():
                    log.info("order already processed, skipping", order_id=order_id)
                    return

            with self.db_conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO orders (id, user_id, status, created_at)
                    VALUES (%s, %s, 'confirmed', NOW())
                    """,
                    (order_id, user_id),
                )

                for item in items:
                    cur.execute(
                        """
                        INSERT INTO order_items (order_id, product_id, quantity)
                        VALUES (%s, %s, %s)
                        """,
                        (order_id, item["product_id"], item["quantity"]),
                    )

                    # Decrement stock atomically — fail if insufficient
                    cur.execute(
                        """
                        UPDATE products
                        SET stock = stock - %s
                        WHERE id = %s AND stock >= %s
                        """,
                        (item["quantity"], item["product_id"], item["quantity"]),
                    )
                    if cur.rowcount == 0:
                        raise ValueError(
                            f"insufficient stock for product {item['product_id']}"
                        )

        log.info("order processed", order_id=order_id, user_id=user_id, item_count=len(items))

    def run(self) -> None:
        self.connect_db()
        log.info("worker started", queue=self.cfg.SQS_QUEUE_URL, env=self.cfg.ENV)

        while self._running:
            response = self.sqs.receive_message(
                QueueUrl=self.cfg.SQS_QUEUE_URL,
                MaxNumberOfMessages=self.cfg.BATCH_SIZE,
                WaitTimeSeconds=self.cfg.WAIT_TIME_SECONDS,
                AttributeNames=["ApproximateReceiveCount"],
            )

            messages = response.get("Messages", [])
            if not messages:
                continue

            for msg in messages:
                receipt = msg["ReceiptHandle"]
                receive_count = int(msg.get("Attributes", {}).get("ApproximateReceiveCount", 1))

                try:
                    body = json.loads(msg["Body"])
                    self.process_message(body)

                    # Delete from SQS only after successful processing
                    self.sqs.delete_message(
                        QueueUrl=self.cfg.SQS_QUEUE_URL,
                        ReceiptHandle=receipt,
                    )

                except (KeyError, ValueError, json.JSONDecodeError) as e:
                    # Malformed message — log and delete to avoid infinite retry
                    log.error("malformed message, discarding", error=str(e), receive_count=receive_count)
                    self.sqs.delete_message(
                        QueueUrl=self.cfg.SQS_QUEUE_URL,
                        ReceiptHandle=receipt,
                    )

                except Exception as e:
                    # Transient failure — leave in queue, SQS will retry
                    log.error("order processing failed, will retry", error=str(e), receive_count=receive_count)

        log.info("worker stopped cleanly")
        if self.db_conn:
            self.db_conn.close()


def main() -> None:
    cfg = Config()
    configure_logging(cfg.ENV)
    worker = OrderWorker(cfg)
    worker.run()


if __name__ == "__main__":
    main()
