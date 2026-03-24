import os


class Config:
    SQS_QUEUE_URL: str = os.environ["SQS_QUEUE_URL"]
    DATABASE_URL: str = os.environ["DATABASE_URL"]
    AWS_REGION: str = os.getenv("AWS_REGION", "ap-south-1")

    # How many messages to pull per SQS receive call (max 10)
    BATCH_SIZE: int = int(os.getenv("BATCH_SIZE", "10"))

    # SQS long-polling wait time in seconds (reduces empty receives, saves cost)
    WAIT_TIME_SECONDS: int = int(os.getenv("WAIT_TIME_SECONDS", "20"))

    # Visibility timeout must exceed max processing time to avoid duplicate delivery
    VISIBILITY_TIMEOUT: int = int(os.getenv("VISIBILITY_TIMEOUT", "60"))

    ENV: str = os.getenv("ENV", "development")
