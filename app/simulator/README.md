# Simulador de sensores

Script local que publica lecturas de temperatura en la cola de ingesta (SQS), a un ritmo fijo de mensajes por segundo. Reemplaza al hardware de campo.

## Formato del mensaje

Un JSON por mensaje, que es el contrato con la Lambda consumidora:

```json
{"sensor_id": "sensor-0007", "timestamp": 1793540000000, "temperature": 24.3}
```

- `sensor_id`: `sensor-0001` a `sensor-NNNN` (según `--sensors`).
- `timestamp`: milisegundos desde 1970. Un mismo sensor nunca repite el valor, porque `sensor_id` + `timestamp` es la clave de la tabla y una repetición pisaría la lectura anterior.
- `temperature`: grados Celsius con un decimal. Normal entre 12 y 32; con probabilidad `--hot-ratio`, entre 35,1 y 42 (dispara la alerta).

## Uso

```bash
python3 -m venv .venv
.venv/bin/pip install -r app/simulator/requirements.txt
```

La URL de la cola sale del estado de OpenTofu, no del código:

```bash
export QUEUE_URL=$(tofu -chdir=infra/envs/dev output -raw ingest_queue_url)
```

```bash
# Prueba corta: 20 mensajes a 5 por segundo, uno de cada cuatro sobre 35 °C
.venv/bin/python app/simulator/simulator.py --count 20 --rate 5 --hot-ratio 0.25

# Prueba de carga: 10.000 mensajes a 100 por segundo (unos 100 s)
.venv/bin/python app/simulator/simulator.py --count 10000 --rate 100

# Sin AWS: imprime los mensajes en pantalla
.venv/bin/python app/simulator/simulator.py --dry-run --count 10
```

| Opción | Por defecto | Qué hace |
|---|---|---|
| `--queue-url` | `$QUEUE_URL` | Cola de ingesta |
| `--count` | 100 | Total de mensajes |
| `--rate` | 10 | Mensajes por segundo |
| `--sensors` | 50 | Sensores distintos |
| `--hot-ratio` | 0.01 | Proporción de lecturas sobre 35 °C |
| `--profile` | sesión actual | Perfil de AWS (para usar la identidad del simulador) |
| `--dry-run` | no | Imprime en vez de enviar |

Los mensajes se envían en lotes de 10 (`SendMessageBatch`), el máximo de SQS: 10.000 mensajes son 1.000 llamadas. El progreso se imprime una vez por segundo y sale con código 1 si algún mensaje falló.

## Credenciales

El simulador solo necesita `sqs:SendMessage` sobre la cola de ingesta; `SendMessageBatch` usa ese mismo permiso. Para no correrlo con los permisos del usuario de cada integrante, el entorno crea el rol `ecobyte-dev-simulador`, que solo puede hacer eso. Nunca se crean access keys.

Una vez, después del deploy, se agrega un perfil que asume ese rol a partir de la sesión de `aws login`:

```bash
aws configure set role_arn "$(tofu -chdir=infra/envs/dev output -raw simulator_role_arn)" --profile ecobyte-simulador
aws configure set source_profile default --profile ecobyte-simulador
aws configure set region us-east-1 --profile ecobyte-simulador
```

Y se corre con ese perfil:

```bash
.venv/bin/python app/simulator/simulator.py --profile ecobyte-simulador --count 50 --rate 10
```

Para comprobar el menor privilegio, el mismo perfil no puede leer la cola:

```bash
aws sqs receive-message --queue-url "$QUEUE_URL" --profile ecobyte-simulador
# AccessDenied: el rol solo tiene sqs:SendMessage
```

El rol confía en la cuenta: lo puede asumir un usuario de la cuenta que tenga permiso de `sts:AssumeRole`, y nadie de afuera. Sin `--profile`, el simulador usa la sesión de `aws login`.
