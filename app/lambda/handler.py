import json
import logging
import math
import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
ALERT_THRESHOLD = float(os.environ["ALERT_THRESHOLD"])
TTL_ATTRIBUTE = os.environ.get("TTL_ATTRIBUTE", "expires_at")
TTL_SECONDS = 30 * 24 * 60 * 60  # 30 días

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Fuera del handler: se crean una vez por entorno de ejecución y se reusan entre invocaciones.
sns = boto3.client("sns")
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def parse_reading(body):
    """Devuelve (sensor_id, timestamp_ms, temperature) o lanza ValueError si el mensaje es inválido."""
    data = json.loads(body)
    if not isinstance(data, dict):
        raise ValueError("el cuerpo no es un objeto JSON")

    sensor_id = data.get("sensor_id")
    timestamp = data.get("timestamp")
    temperature = data.get("temperature")

    if not isinstance(sensor_id, str) or not sensor_id:
        raise ValueError("sensor_id ausente o no es texto")
    if isinstance(timestamp, bool) or not isinstance(timestamp, int) or timestamp <= 0:
        raise ValueError("timestamp ausente o no es un entero positivo (ms)")
    if isinstance(temperature, bool) or not isinstance(temperature, (int, float)):
        raise ValueError("temperature ausente o no es numérica")
    if not math.isfinite(temperature):
        raise ValueError("temperature no es finita")

    return sensor_id, timestamp, float(temperature)


def save_reading(sensor_id, timestamp, temperature):
    """Guarda la lectura. La clave (sensor_id, timestamp) hace que reintentar sea idempotente."""
    table.put_item(
        Item={
            "sensor_id": sensor_id,
            "timestamp": timestamp,
            # DynamoDB no acepta float: se pasa por str para no arrastrar error binario.
            "temperature": Decimal(str(temperature)),
            # Epoch en segundos, que es lo que espera el TTL de DynamoDB.
            TTL_ATTRIBUTE: timestamp // 1000 + TTL_SECONDS,
        }
    )


def format_ts(timestamp_ms):
    """Epoch en milisegundos -> '2026-11-18 14:32:07 UTC' (legible en el email)."""
    dt = datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M:%S UTC")


def publish_alert(hot):
    """Un solo email por lote, con todas las lecturas sobre el umbral."""
    lines = [f"- {sid}: {temp:.1f} °C ({format_ts(ts)})" for sid, ts, temp, _ in hot]
    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject=f"EcoByte: {len(hot)} lectura(s) sobre {ALERT_THRESHOLD:g} °C"[:100],
        Message=f"Lecturas por encima de {ALERT_THRESHOLD:g} °C:\n" + "\n".join(lines),
    )


def handler(event, context):
    failures = []
    hot = []  # (sensor_id, timestamp, temperature, message_id)

    for record in event["Records"]:
        message_id = record["messageId"]
        try:
            sensor_id, timestamp, temperature = parse_reading(record["body"])
        except (ValueError, json.JSONDecodeError) as exc:
            # Mensaje inválido: reintentar no lo arregla, pero se reporta para que llegue a la DLQ
            # y la alarma avise. El motivo no viaja a la DLQ, por eso se loguea acá.
            logger.error("mensaje inválido messageId=%s motivo=%s", message_id, exc)
            failures.append({"itemIdentifier": message_id})
            continue

        try:
            save_reading(sensor_id, timestamp, temperature)
        except Exception:
            logger.exception("no se pudo guardar messageId=%s sensor_id=%s", message_id, sensor_id)
            failures.append({"itemIdentifier": message_id})
            continue

        if temperature > ALERT_THRESHOLD:
            hot.append((sensor_id, timestamp, temperature, message_id))

    if hot:
        try:
            publish_alert(hot)
        except Exception:
            # Ya están guardadas: el reintento las vuelve a escribir igual (misma clave) y
            # reintenta el aviso. Se reportan solo las lecturas calientes.
            logger.exception("no se pudo publicar la alerta (%d lecturas)", len(hot))
            for sensor_id, _, _, message_id in hot:
                logger.error("alerta fallida messageId=%s sensor_id=%s", message_id, sensor_id)
                failures.append({"itemIdentifier": message_id})

    logger.info(
        "lote procesado: total=%d fallidos=%d sobre_umbral=%d",
        len(event["Records"]), len(failures), len(hot),
    )
    return {"batchItemFailures": failures}
