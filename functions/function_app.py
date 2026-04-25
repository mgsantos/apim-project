import azure.functions as func
import json
import logging

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
