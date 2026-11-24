# Seguridad

[← Volver al README](../README.md)

- **Menor privilegio.** La Lambda solo puede leer y borrar de su cola, escribir en su tabla, publicar en su tópico y escribir sus logs. El rol de despliegue solo administra recursos `ecobyte-*` y no puede modificar los roles de GitHub.
- **Sin claves.** GitHub entra a AWS con OIDC: el rol de plan solo acepta tokens de PRs, y el de deploy solo del environment `dev` aprobado.
- **Sin secretos en el repo.** Los correos están cifrados en SSM. No se versionan `.terraform/`, `*.tfstate*` ni `tfplan`.
- **Cifrado y escaneo.** Estado en S3 cifrado; colas y tabla cifradas; Trivy en cada PR.
