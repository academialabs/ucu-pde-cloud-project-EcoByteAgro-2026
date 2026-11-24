# Despliegue y destrucción

[← Volver al README](../README.md)

Qué hace falta, cómo se prepara la cuenta una sola vez, cómo entra cada cambio y cómo se crea y se borra el entorno.

- [Requisitos](#requisitos)
- [1. Una sola vez: bases de la cuenta](#1-una-sola-vez-bases-de-la-cuenta)
- [2. Cada cambio: pull request](#2-cada-cambio-pull-request)
- [3. Desplegar el entorno](#3-desplegar-el-entorno)
- [Destruir](#destruir)

## Requisitos

- Cuenta de AWS con un usuario IAM con MFA (nunca la cuenta root).
- [OpenTofu](https://opentofu.org) 1.12.6, AWS CLI 2.36.25 o más nuevo, Python 3 y `gh`.
- Para revisar antes de un PR: tflint 0.65.0 y Trivy 0.76.1.

Credenciales: localmente se usa `aws login` y en el pipeline, OIDC. No se crean access keys de larga duración.

## 1. Una sola vez: bases de la cuenta

Se crean a mano, porque OpenTofu los necesita antes de poder correr:

- El bucket del estado, `ecobyte-agro-tfstate-<cuenta>`, con versionado, cifrado AES256 y sin acceso público.
- Los parámetros `SecureString` `/ecobyte/budget-emails` y `/ecobyte/alert-emails`, cada uno con una lista JSON de correos. Así los correos no quedan en el repo.

Después se aplica el bootstrap desde la laptop. Crea el presupuesto de USD 5 por mes, el proveedor OIDC de GitHub y los roles `ecobyte-github-plan` (solo lectura, para PRs) y `ecobyte-github-deploy`:

```bash
aws login
cd infra/bootstrap
tofu init
tofu plan
tofu apply
```

En GitHub hacen falta:

- Las variables de Actions `AWS_PLAN_ROLE_ARN` y `AWS_DEPLOY_ROLE_ARN`, con los ARN de los dos roles.
- Un environment `dev` con aprobación manual y despliegue solo desde `master`.

## 2. Cada cambio: pull request

Todo cambio entra por un PR a `master`, que está protegida. El workflow `ci` corre `tofu fmt`, `validate`, `tflint` y Trivy, y publica el `tofu plan` como comentario en el PR.

Para revisar lo mismo localmente antes de abrir el PR:

```bash
tofu fmt -check -recursive infra
tflint --chdir=infra --recursive
trivy config --severity HIGH,CRITICAL infra
```

## 3. Desplegar el entorno

En GitHub: **Actions → deploy → Run workflow**. El job espera la aprobación del environment `dev` y después corre `tofu plan` y `tofu apply` con el rol de despliegue.

Después del primer deploy, cada correo recibe un email de AWS para **confirmar la suscripción** al tópico de alertas. Sin confirmarla no llegan los avisos. Hay que repetirlo cada vez que se recrea el entorno.

Con el entorno arriba, sigue [Uso](uso.md).

## Destruir

En GitHub: **Actions → destroy → Run workflow**, con la misma aprobación que el deploy. Corre `tofu plan -destroy` y lo aplica.

Se destruye al terminar cada sesión de trabajo. El bootstrap (presupuesto, OIDC y roles) no se destruye: no tiene costo y lo necesita el pipeline.
