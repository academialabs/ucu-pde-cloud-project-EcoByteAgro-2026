# EcoByte Agro

Telemetría de sensores de cultivo en AWS. Proyecto integrador de Cloud Computing (UCU), proyecto 5.

Un simulador publica lecturas de temperatura en una cola. Una función las procesa, las guarda 30 días y avisa por email si alguna supera 35 °C. El foco es la infraestructura: el código de la aplicación es mínimo a propósito, y todo lo demás está definido con OpenTofu y se despliega por un pipeline.

![Arquitectura en AWS](docs/diagramas/arquitectura-aws.png)

## Documentación

| Tema | Qué tiene |
|---|---|
| [Arquitectura](docs/arquitectura.md) | Cómo viaja una lectura, paso a paso, y qué recurso de AWS cumple cada función. |
| [Diagramas](docs/diagramas.md) | Contexto, arquitectura, despliegue, componentes de la función, flujos, casos de uso y secuencia. |
| [Despliegue y destrucción](docs/despliegue.md) | Requisitos, preparación de la cuenta, pull requests, deploy y destroy desde GitHub Actions. |
| [Uso](docs/uso.md) | Cómo correr el simulador y dónde ver el resultado: dashboard, tabla, logs y email. |
| [Simulador](app/simulator/README.md) | Formato del mensaje, todas las opciones y credenciales del simulador. |
| [Seguridad](docs/seguridad.md) | Menor privilegio, OIDC sin claves, secretos en SSM, cifrado y escaneo. |
| [FinOps](docs/finops.md) | Presupuesto y avisos, costo real y medidas de ahorro. |
| [Escalabilidad](docs/escalabilidad.md) | Proyección a 10x y 100x, costo, cuello de botella y qué cambiar para crecer. |
| [Pruebas de carga](docs/pruebas-de-carga.md) | Resultados y capturas de las pruebas de 10.000 y 40.000 lecturas. |
| [Elección de provider](docs/provider-aws.md) | Por qué AWS y las equivalencias en otros proveedores. |

## En resumen

- **Prueba de carga:** con cuatro simuladores (40.000 lecturas a unos 222 por segundo) la cola llegó a 21.100 mensajes y se vació unos 5 minutos después, sin errores ni mensajes en la DLQ. [Ver las pruebas](docs/pruebas-de-carga.md).
- **Costo:** unos USD 0,10 en todo el proyecto, con un presupuesto de USD 5 por mes. Sin tráfico, el costo es cero. [Ver FinOps](docs/finops.md).
- **Despliegue:** todo cambio entra por PR y el pipeline aplica con aprobación manual. El entorno se destruye al terminar cada sesión. [Ver despliegue](docs/despliegue.md).

## Estructura del repo

```
app/lambda/          función consumidora (handler.py)
app/simulator/       simulador de sensores (ver su README)
infra/bootstrap/     presupuesto y OIDC de GitHub; se aplica una vez desde la laptop
infra/modules/       messaging, database, consumer, monitoring
infra/envs/dev/      conecta los módulos; lo aplica el pipeline
.github/workflows/   ci.yml, deploy.yml, destroy.yml
docs/                documentación enlazada arriba, diagramas y capturas
```
