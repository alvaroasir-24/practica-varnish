# T6. Logs: estadísticas e incidencias (criterio i)

> **Estado:** Configurado el reenvío de IP real (`HAProxy → Varnish → Apache`), instalado y probado **GoAccess 1.9.3** y analizada la seguridad del tráfico interno. Queda pendiente definir el formato `tiempos` (`%D` / `$request_time`), comandos `awk`/`sort`/`uniq`, proteger `/stats/` con Basic, resolver `incidencias.tar.gz` y configurar `fail2ban` / `limit_req`.

## 1. Reenvío de IP real y auditoría (`option forwardfor` + `mod_remoteip`)
- **Problemas sin reenvío de IP:** Todos los registros en Apache muestran la IP del proxy (`172.31.33.114`), provocando pérdida de trazabilidad forense, analítica web falsa, riesgo de auto-bloqueo con Fail2Ban al propio proxy e inutilización de controles/límites por IP.
- **Solución implementada:**
  1. `option forwardfor` en `/etc/haproxy/haproxy.cfg`.
  2. `a2enmod remoteip` + [remoteip.conf](../configs/remoteip.conf) (`RemoteIPHeader X-Forwarded-For`, `RemoteIPInternalProxy 127.0.0.1 172.31.33.114`).
  3. Cambio de `%h` a **`%a`** en `LogFormat` de `/etc/apache2/apache2.conf`.
- **Verificación en `/var/log/apache2/access.log`:**
  ```text
  80.31.44.195 - - [25/Nov/2026:08:31:03 +0000] "GET /?test_goaccess=1 HTTP/1.1" 200 3561 "-" "curl/8.18.0"
  ```

## 2. Monitorización con GoAccess
- **Tiempo real en terminal:** `goaccess /var/log/apache2/access.log --log-format=COMBINED`
- **Reporte HTML:** `goaccess /var/log/apache2/access.log -o /var/www/html/report.html --log-format=COMBINED`
- **Errores HTTP (`403`, `404`, `400`):** Varnish no cachea errores `403`, por lo que siempre pasan a Apache y aparecen desglosados en el panel `HTTP Status Codes` de GoAccess. Las entradas `"\x16\x03\x01..." 400` en `other_vhosts_access.log` corresponden a conexiones TLS enviadas al puerto 80 HTTP plano.

## 3. Seguridad del tráfico HTTP interno y alternativas
- **Riesgos en AWS:** Sin restringir el Security Group de Apache, el puerto 80 queda expuesto a escaneos directos (*bypass* de HAProxy/Varnish y posible *header spoofing*). Mitigación: permitir puerto 80 en Apache **solo desde `172.31.33.114/32`**.
- **Alternativas comparadas:** HAProxy solo (soporta HTTPS *End-to-End*, caché básica), Nginx (`proxy_cache` + TLS todo en uno), Hitch + Varnish (terminador TLS ligero con protocolo `PROXY`) y AWS ALB / CloudFront.
