import azure.functions as func
import json
import logging
import os
import uuid
from datetime import datetime, timezone

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

PRODUCTS = [
    {"id": "PROD-001", "name": "Wireless Mouse", "price": 29.99},
    {"id": "PROD-002", "name": "Mechanical Keyboard", "price": 89.99},
    {"id": "PROD-003", "name": "USB-C Hub", "price": 49.99},
]


@app.route(route="products", methods=["GET"])
def get_products(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("GET /api/products called")
    return func.HttpResponse(
        body=json.dumps(PRODUCTS),
        mimetype="application/json",
        status_code=200,
    )


@app.route(route="orders", methods=["POST"])
def create_order(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("POST /api/orders called")

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            body=json.dumps({"error": "Invalid JSON body"}),
            mimetype="application/json",
            status_code=400,
        )

    customer_name = body.get("customer_name")
    product_id = body.get("product_id")
    quantity = body.get("quantity")

    if not all([customer_name, product_id, quantity]):
        return func.HttpResponse(
            body=json.dumps({"error": "Missing required fields: customer_name, product_id, quantity"}),
            mimetype="application/json",
            status_code=400,
        )

    order_id = str(uuid.uuid4())
    order_event = {
        "order_id": order_id,
        "customer_name": customer_name,
        "product_id": product_id,
        "quantity": quantity,
        "status": "pending",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    # Publish to Service Bus
    try:
        from azure.servicebus import ServiceBusClient, ServiceBusMessage

        conn_str = os.environ.get("SERVICE_BUS_CONNECTION_STRING")
        if conn_str:
            with ServiceBusClient.from_connection_string(conn_str) as client:
                sender = client.get_topic_sender(topic_name="orders-topic")
                with sender:
                    message = ServiceBusMessage(json.dumps(order_event))
                    sender.send_messages(message)
            logging.info(f"Order {order_id} published to Service Bus")
        else:
            logging.warning(f"Order {order_id} created but SERVICE_BUS_CONNECTION_STRING not set — skipping publish")
    except Exception as e:
        logging.error(f"Order {order_id} failed to publish to Service Bus: {e}")
        # Still return 202 — the order was accepted, async processing may retry later

    return func.HttpResponse(
        body=json.dumps({"order_id": order_id, "status": "pending"}),
        mimetype="application/json",
        status_code=202,
    )
