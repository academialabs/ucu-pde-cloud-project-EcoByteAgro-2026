# Uso

[← Volver al README](../README.md)

Cómo mandar lecturas con el simulador y dónde ver el resultado. Requiere el entorno desplegado (ver [Despliegue](despliegue.md)).

## Correr el simulador

```bash
python3 -m venv .venv
.venv/bin/pip install -r app/simulator/requirements.txt
export QUEUE_URL=$(tofu -chdir=infra/envs/dev output -raw ingest_queue_url)

# 50 lecturas a 10 por segundo, una de cada cinco sobre 35 °C
.venv/bin/python app/simulator/simulator.py --count 50 --rate 10 --hot-ratio 0.2
```

Para leer el output hace falta `tofu init` en `infra/envs/dev`, con la sesión de `aws login` activa. Todas las opciones del simulador están en [su README](../app/simulator/README.md).

## Qué mirar

- **Dashboard** `ecobyte-dev-dashboard` en CloudWatch: mensajes en la cola y en la DLQ, invocaciones, errores, duración y concurrencia de la Lambda.
- **Tabla** `ecobyte-dev-lecturas` en DynamoDB: las lecturas guardadas, cada una con su `expires_at`.
- **Logs** `/aws/lambda/ecobyte-dev-consumidor`: una línea `lote procesado` por invocación, con el total, los fallidos y las lecturas sobre el umbral.
- **Email** de alerta en los correos suscritos.
