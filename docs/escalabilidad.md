# Escalabilidad

[← Volver al README](../README.md)

Qué pasa si los sensores crecen 10 y 100 veces: dónde se traba primero, cuánto cuesta y qué habría que cambiar. Las mediciones salen de las [pruebas de carga](pruebas-de-carga.md); el resto son estimaciones con precios de lista de AWS (`us-east-1`, consultados el 3 de noviembre de 2026).

## Resumen

| Pregunta | Respuesta |
|---|---|
| ¿Qué se traba primero? | La concurrencia de la Lambda: procesa unos 84 mensajes por segundo con `max_concurrency = 5`. 10x ya la supera. |
| ¿Cómo se arregla? | Pedir más cuota de concurrencia (la cuenta tiene 10), subir `max_concurrency` y escribir en lotes en DynamoDB. |
| ¿Qué crece más en costo? | Las escrituras en DynamoDB, cerca del 50 % del total. |
| ¿Qué no escala por diseño? | Una alerta por email por lectura caliente. |
| ¿Qué escala sin cambios? | SQS y el almacenamiento de DynamoDB (el TTL limita lo guardado a 30 días). |

## Escenarios

Supuestos: cada sensor manda 1 lectura por minuto, el 1 % pasa de 35 °C y hay 2 suscriptores de alertas.

| | Base | 10x | 100x |
|---|---|---|---|
| Sensores | 1.000 | 10.000 | 100.000 |
| Mensajes por segundo | 17 | 167 | 1.667 |
| Lambdas en paralelo necesarias | 1 | 10 | 99 |
| Emails de alerta por segundo (por suscripción) | 0,2 | 1,7 | 16,7 |
| Datos guardados en DynamoDB | 9 GB | 86 GB | 864 GB |

Las Lambdas necesarias salen de lo medido: cada ejecución procesó unos 17 mensajes por segundo. Solo se probó con 5 en paralelo, así que con más es una proyección.

## Costo mensual estimado (USD)

| Servicio | Base | 10x | 100x |
|---|---|---|---|
| SQS | 5 | 52 | 518 |
| Lambda | 4 | 37 | 370 |
| DynamoDB, escrituras | 27 | 270 | 2.700 |
| DynamoDB, almacenamiento | 2 | 22 | 216 |
| SNS, emails | 17 | 173 | 1.728 |
| CloudWatch Logs | 1 | 11 | 108 |
| **Total** | **~56** | **~565** | **~5.640** |

Sin capa gratuita, para poder comparar. El costo crece lineal con los sensores, como se espera en serverless: se paga por uso, no por capacidad reservada.

## Cuello de botella: la concurrencia de la Lambda

| Escenario | Llegan | Se procesan | Resultado |
|---|---|---|---|
| Base | 17/s | ~84/s | Sobra capacidad |
| 10x | 167/s | ~84/s | La cola crece: ya satura |
| 100x | 1.667/s | ~84/s | Llegan 20 veces más de lo que se procesa |

Con cuatro simuladores a 222 mensajes por segundo, un ritmo parecido a 10x, la cola llegó a 21.100 mensajes y se vació 5 minutos después de terminar el envío, sin perder nada. Para sostener 10x o 100x:

1. **Pedir más concurrencia para la cuenta** en Service Quotas. El límite es 10, muy por debajo de los 1.000 habituales.
2. **Subir `max_concurrency`**, que es una variable del módulo `consumer`: unas 10 para 10x y unas 100 para 100x.
3. **Escribir en lotes** con `batch_write_item` (hasta 25 ítems por llamada) en vez de un `put_item` por lectura. Baja el tiempo por lote sin subir la concurrencia.

El límite de concurrencia también protege a la base: si los sensores mandan todos a la vez, SQS absorbe el pico y la Lambda lo saca a un ritmo que DynamoDB aguanta. Una tabla on-demand nueva soporta unas 4.000 escrituras por segundo y puede rechazar escrituras si el pico se duplica de golpe. SQS no es el límite: las colas estándar no tienen tope de mensajes por segundo ni de mensajes en espera.

## Lo que más cuesta: escrituras en DynamoDB

DynamoDB cobra cada escritura por separado, mientras que SQS y Lambda trabajan en lotes de 10. Formas de bajarlo:

- Guardar un promedio por sensor por minuto o por hora en vez de cada lectura.
- Bajar la frecuencia de los sensores: una lectura cada 5 minutos divide el costo por 5.
- Con carga estable, comparar con capacidad aprovisionada.

## Lo que no escala: una alerta por lectura

Con 1 % de lecturas calientes, casi cada alerta es un email. En 100x serían 16,7 emails por segundo por suscripción, y SNS permite como máximo 10, sin posibilidad de aumento. Además, nadie puede leer tantas alertas.

La solución es agrupar: una alerta por sensor cada 15 minutos, o un resumen periódico. Para la demo no hace falta, pero sería el primer cambio si el sistema creciera.

## Pendiente

- Pedir el aumento de la cuota de concurrencia (necesario para 10x y 100x).
- Cargar los tres escenarios en la [calculadora de AWS](https://calculator.aws) y adjuntar el link.

## Fuentes

- [Escalado de Lambda con SQS](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html) y [límites de Lambda](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)
- Límites de SQS: [mensajes](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html) y [colas](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-queues.html)
- [DynamoDB on-demand](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/on-demand-capacity-mode.html) y [límites de SNS](https://docs.aws.amazon.com/general/latest/gr/sns.html)
- Precios: [SQS](https://aws.amazon.com/sqs/pricing/), [Lambda](https://aws.amazon.com/lambda/pricing/), [DynamoDB](https://aws.amazon.com/dynamodb/pricing/on-demand/), [SNS](https://aws.amazon.com/sns/pricing/), [CloudWatch](https://aws.amazon.com/cloudwatch/pricing/)
