# Práctica: Aceleración Web con Varnish Cache, Terminación SSL con HAProxy y Benchmarking con ApacheBench (ab)

Este repositorio contiene la configuración, pruebas de carga y comparativa de rendimiento entre un servidor web **Apache HTTP Server** y el acelerador de caché web **Varnish Cache**, junto con la terminación SSL mediante **HAProxy** para soporte seguro **HTTPS (Let's Encrypt / Certbot)**, desplegados sobre instancias **Debian 13 (Trixie)** en **Amazon Web Services (AWS)**.

---

## 1. Arquitectura del Despliegue en AWS EC2

Se ha implementado una arquitectura profesional en dos capas (*two-tier*) con terminación SSL en el frontend:

```text
Internet / Cliente / Navegador
        │
        ▼ (HTTPS / Puerto 443 con Certificado Let's Encrypt)
┌────────────────────────────────────────────────────────┐
│  MÁQUINA 2 - FRONTEND (IP Pública: 54.224.12.19)       │
│                                                        │
│   ┌──────────────┐                                     │
│   │   HAProxy    │  <-- Escucha en *:443               │
│   └──────────────┘      Termina SSL (amr234.ddns.net)  │
│          │                                             │
│          ▼ (HTTP plano interno / 127.0.0.1:80)         │
│   ┌──────────────┐                                     │
│   │   Varnish    │  <-- Escucha en *:80                │
│   └──────────────┘      Caché en memoria RAM (malloc)  │
└──────────┬─────────────────────────────────────────────┘
           │
           │ (En caso de MISS por red privada de AWS)
           ▼ (HTTP plano / 172.31.17.33:80)
┌────────────────────────────────────────────────────────┐
│  MÁQUINA 1 - BACKEND (IP Privada: 172.31.17.33)        │
│   ┌──────────────┐                                     │
│   │    Apache    │  <-- Servidor web original          │
│   └──────────────┘      Generación de contenido        │
└────────────────────────────────────────────────────────┘
```

### Detalle de los Componentes:
1. **Frontend (Máquina 2):**
   - **HAProxy 3.0:** Escucha en el puerto `443` con soporte **HTTP/2** y gestiona el certificado SSL de Let's Encrypt para `amr234.ddns.net`. Desencripta el tráfico y añade la cabecera `X-Forwarded-Proto: https`.
   - **Varnish Cache 7.7:** Escucha en el puerto `80`. Almacena en memoria RAM (`malloc,256m`) las respuestas del backend y las entrega directamente al cliente (vía HTTP) o a HAProxy (vía HTTPS).

2. **Backend (Máquina 1):**
   - **Apache 2.4:** Escucha en `172.31.17.33:80`. Contiene la web original y redirige a HTTPS únicamente si la cabecera `X-Forwarded-Proto` no indica que el tráfico ya venía cifrado.

---

## 2. Configuración de los Servicios

### 2.1. Terminación SSL con HAProxy (`/etc/haproxy/haproxy.cfg`)
HAProxy recibe el tráfico en el puerto 443, utiliza el certificado unificado `.pem` y reenvía a Varnish en `127.0.0.1:80`:

```haproxy
frontend https_in
    option forwardfor
    bind *:443 ssl crt /etc/haproxy/certs/amr234.ddns.net.pem alpn h2,http/1.1
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-Port %[dst_port]
    default_backend varnish_pool

backend varnish_pool
    server varnish1 127.0.0.1:80 check
```

### 2.2. Aceleración con Varnish (`/etc/varnish/default.vcl`)
Varnish se conecta con la IP privada de Apache y marca las cabeceras `X-Cache` para auditoría:

```vcl
vcl 4.1;

backend default {
    .host = "172.31.17.33";
    .port = "80";
}

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
```

### 2.3. Configuración de Systemd para Varnish
Para Debian 13 (`Type=exec`), se configuró el override en `/etc/systemd/system/varnish.service.d/override.conf`:

```ini
[Service]
ExecStart=
ExecStart=/usr/sbin/varnishd \
          -F \
          -a :80 \
          -T localhost:6082 \
          -f /etc/varnish/default.vcl \
          -S /etc/varnish/secret \
          -p feature=+http2 \
          -s malloc,256m
```

### 2.4. Ajuste en Apache (`000-default.conf`)
Para evitar bucles infinitos de redirección 301, se ajustó la condición de Rewrite:
```apache
RewriteEngine on
RewriteCond %{SERVER_NAME} =amr234.ddns.net
RewriteCond %{HTTP:X-Forwarded-Proto} !https
RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
```

---

## 3. Verificación de Funcionamiento HTTPS con Varnish

Petición de prueba con `curl` sobre el puerto seguro HTTPS (443):

```bash
curl -I https://amr234.ddns.net/
```

**Respuesta obtenida:**
```http
HTTP/2 200 
date: Wed, 18 Nov 2026 08:42:10 GMT
server: Apache/2.4.71 (Debian)
via: 1.1 ip-172-31-33-114 (Varnish/7.7)
x-cache: HIT
age: 3
content-length: 11805
```

> **Verificación:** La conexión se establece vía **HTTP/2 (HTTPS)** con certificado SSL válido, entregada desde la memoria de **Varnish (`x-cache: HIT`)** y descargando al servidor **Apache**.

---

## 4. Pruebas de Rendimiento con ApacheBench (`ab`)

Se realizaron pruebas con un volumen de **5.000 peticiones** y una concurrencia de **100 usuarios simultáneos**:

```bash
# Test 1: Apache Directo (Línea base)
ab -n 5000 -c 100 -g data/apache_bench.tsv http://172.31.17.33/ > data/apache_summary.txt

# Test 2: Varnish Cache (Acelerado)
ab -n 5000 -c 100 -g data/varnish_bench.tsv http://localhost/ > data/varnish_summary.txt
```

### Resultados Comparativos

| Métrica | Apache Directo | Varnish Cache |
| :--- | :---: | :---: |
| **Total de Peticiones** | 5.000 | 5.000 |
| **Concurrencia Simultánea** | 100 | 100 |
| **Peticiones Fallidas** | 0 | 0 |
| **Throughput (Requests/sec)** | **8.803,28 #/seg** | **6.821,42 #/seg** |
| **Tiempo Medio por Petición** | 11,359 ms | 14,660 ms |
| **Peticiones al Servidor Apache** | **5.000 procesadas** | **1 sola petición (MISS inicial)** |

---

## 5. Visualización con Gnuplot

Los datos tabulares del benchmark (`-g`) fueron procesados con **Gnuplot** (`scripts/generar_grafica.gp`).

![Comparativa de Rendimiento](graphs/comparativa_rendimiento.png)

---

## 6. Persistencia, Auditoría y Reenvío de IP Real (`HAProxy → Varnish → Apache`)

### 6.1. Problemas de Auditoría y Persistencia sin Reenvío de IP
Al trabajar detrás de un proxy inverso y una caché HTTP, Apache recibe las conexiones TCP desde la IP privada de la máquina de Varnish (`172.31.33.114`). Si no se propaga la IP pública del cliente, aparecen los siguientes problemas:
- **Pérdida de trazabilidad forense:** Todos los accesos en `/var/log/apache2/access.log` y `error.log` muestran `172.31.33.114`, impidiendo identificar el origen real de ataques o escaneos.
- **Analítica web distorsionada:** Herramientas de estadísticas registran un único visitante (`172.31.33.114`) generando todo el tráfico.
- **Bloqueo accidental con Fail2Ban / WAF:** Si un sistema de defensa banea por número de errores en `access.log`, acabará bloqueando la IP del proxy y dejando sin servicio a todos los usuarios.
- **Persistencia y límites por IP:** Cualquier control de acceso (`Require ip`), *rate limiting* o persistencia de sesión basada en `REMOTE_ADDR` aplicará el mismo límite compartido a todos los clientes reales.
- **Visibilidad parcial por caché:** Los `HIT` servidos por Varnish desde RAM no llegan a Apache; para auditarlos se consulta el log de HAProxy (`journalctl -u haproxy`) o `varnishncsa`.

### 6.2. Solución Implementada
1. **HAProxy (`/etc/haproxy/haproxy.cfg`):** Se añadió `option forwardfor` en `frontend https_in` para inyectar la cabecera HTTP `X-Forwarded-For` con la IP pública real del cliente.
2. **Varnish (`/etc/varnish/default.vcl`):** Su VCL interna conserva la cabecera `X-Forwarded-For` recibida de HAProxy añadiendo `127.0.0.1` al final de la cadena.
3. **Apache (`mod_remoteip` y `LogFormat`):**
   - Se habilitó el módulo: `a2enmod remoteip`
   - Se configuró `/etc/apache2/conf-available/remoteip.conf`:
     ```apache
     RemoteIPHeader X-Forwarded-For
     RemoteIPInternalProxy 127.0.0.1 172.31.33.114
     ```
   - En `/etc/apache2/apache2.conf` se sustituyó `%h` (IP de conexión TCP) por **`%a`** (IP real del cliente resuelta por `mod_remoteip`) en `LogFormat`.

**Verificación real en `/var/log/apache2/access.log`:**
```text
80.31.44.195 - - [25/Nov/2026:08:31:03 +0000] "GET /?test_goaccess=1 HTTP/1.1" 200 3561 "-" "curl/8.18.0"
```

---

## 7. Monitorización y Análisis de Logs con GoAccess

Se instaló **GoAccess 1.9.3** en la máquina backend de Apache para analizar `/var/log/apache2/access.log` con las IPs reales ya corregidas:

- **Monitorización en tiempo real desde terminal:**
  ```bash
  goaccess /var/log/apache2/access.log --log-format=COMBINED
  ```
- **Generación de reporte web HTML (`/var/www/html/report.html`):**
  ```bash
  goaccess /var/log/apache2/access.log -o /var/www/html/report.html --log-format=COMBINED
  ```

### Comportamiento de Errores HTTP (`403`, `404`, `400`)
- En el panel **HTTP Status Codes** de GoAccess se desglosan los códigos `2xx`, `3xx` y `4xx Client Errors` (pulsando `Enter` sobre `4xx` en la terminal o clic en el HTML).
- Por defecto, **Varnish no cachea errores `403 Forbidden`**, por lo que siempre pasan a Apache y quedan auditados con la IP real en `access.log` y el detalle en `error.log`.
- Las entradas `"\x16\x03\x01..." 400` en `other_vhosts_access.log` corresponden a intentos de conexión HTTPS (TLS *ClientHello*) enviados por error al puerto 80 HTTP plano.

---

## 8. Seguridad del Tráfico HTTP y Alternativas de Arquitectura

### 8.1. Riesgos de usar HTTP Plano en la Arquitectura
1. **Hacia el cliente (puerto 80):** Tráfico en texto plano (*sniffing* de cookies/credenciales), ataques *Man-in-the-Middle*, suplantación de servidor y ausencia de HTTP/2.
2. **En el tramo interno (`HAProxy → Varnish → Apache`):**
   - **Bypass directo al backend:** Si el Security Group de Apache deja el puerto `80` abierto a `0.0.0.0/0`, bots y atacantes pueden conectarse directamente a la IP pública de Apache saltándose HAProxy y Varnish.
   - **Suplantación de cabeceras (*Header Spoofing*):** Si cualquiera puede acceder directo al puerto 80 de Apache, podría falsificar `X-Forwarded-For` o `X-Forwarded-Proto`.
   - **Tráfico interno sin cifrar en VPC:** Entre Varnish (`172.31.33.114`) y Apache (`172.31.17.33`) el tráfico viaja en HTTP plano dentro de la red interna de AWS.
   - **Fuga o envenenamiento de caché:** Cachear por error respuestas con `Set-Cookie` o contenido privado en Varnish.
- **Mitigación recomendada en AWS:** Restringir la regla de entrada del puerto `80` en el Security Group de la máquina **Apache** únicamente a la IP privada de **Varnish (`172.31.33.114/32`)** y redirigir HTTP a HTTPS en el frontend.

### 8.2. Comparativa de Alternativas
| Arquitectura | Ventajas | Desventajas |
| :--- | :--- | :--- |
| **HAProxy + Varnish + Apache (Actual)** | Máximo rendimiento en caché (VCL, *grace mode*, purgado) + terminación SSL robusta con HTTP/2. | Mayor complejidad (3 servicios); tramo interno Varnish → Apache va en HTTP salvo usar túnel (WireGuard/stunnel). |
| **HAProxy solo (sin Varnish)** | Menos complejidad; soporta **HTTPS End-to-End** hacia Apache; HAProxy 3.0 incluye caché básica en RAM. | Caché muy limitada frente a Varnish para sitios dinámicos o reglas avanzadas. |
| **Nginx (SSL + `proxy_cache`)** | Todo en un único servicio: terminador TLS, caché en RAM/disco y cifrado hacia el backend. | Menos programable que el lenguaje VCL de Varnish. |
| **Hitch + Varnish** | Terminador TLS oficial y ultraligero de Varnish con soporte nativo de protocolo `PROXY`. | Solo descifra TLS; sin balanceo ni ACLs/rate-limit avanzados. |
| **AWS ALB / CloudFront** | Certificados gestionados (ACM), protección DDoS y backend en subred privada sin IP pública. | Dependencia de servicios gestionados de AWS. |

---

## 9. Estructura del Repositorio

```text
practica-varnish/
├── configs/
│   ├── default.vcl           # Configuración VCL de Varnish (Backend y cabeceras HIT/MISS)
│   ├── haproxy.cfg           # Configuración de HAProxy (SSL puerto 443 + option forwardfor)
│   ├── override.conf         # Override de systemd para Varnish en el puerto 80
│   └── remoteip.conf         # Configuración de mod_remoteip en Apache para IP real
├── data/
│   ├── apache_bench.tsv      # Datos de latencia de Apache directo
│   ├── apache_summary.txt    # Resumen numérico de Apache
│   ├── varnish_bench.tsv     # Datos de latencia de Varnish
│   └── varnish_summary.txt   # Resumen numérico de Varnish
├── graphs/
│   └── comparativa_rendimiento.png  # Gráfica comparativa generada con Gnuplot
├── scripts/
│   └── generar_grafica.gp    # Script de Gnuplot
└── README.md                 # Documentación técnica completa
```
