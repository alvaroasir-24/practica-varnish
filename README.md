# Práctica: Aceleración Web con Varnish Cache y Benchmarking con ApacheBench (ab)

Este repositorio contiene la configuración, pruebas de carga y comparativa de rendimiento entre un servidor web **Apache HTTP Server** y el acelerador de caché web **Varnish Cache**, desplegados sobre instancias **Debian 13 (Trixie)** en **Amazon Web Services (AWS)**.

---

## 1. Arquitectura del Despliegue en AWS EC2

Se ha implementado una arquitectura en dos capas (*two-tier*) dentro de la misma VPC de AWS:

```text
[ Cliente / ApacheBench ]
        │
        ├──> Petición Directa (Línea Base):  http://<IP_APACHE>:80/
        │
        └──> Petición Acelerada (Varnish):   http://<IP_VARNISH>:80/
                                                     │
                                                     ▼ (En caso de MISS)
                                            http://172.31.17.33:80 (Apache)
```

### Detalle de las Instancias:
1. **Instancia 1 - Servidor Web Backend (Apache):**
   - **IP Privada:** `172.31.17.33`
   - **Servidor:** Apache/2.4.71 (Debian)
   - **Servicio:** Escucha en el puerto 80 (HTTP) y 443 (HTTPS mediante Let's Encrypt / Certbot con dominio `amr234.ddns.net`).
   - **Función:** Generación y entrega del contenido original.

2. **Instancia 2 - Proxy Inverso y Acelerador (Varnish Cache):**
   - **IP Privada:** `172.31.33.114`
   - **Servidor:** Varnish Cache 7.7.0 (Debian)
   - **Servicio:** Escucha en el puerto público 80.
   - **Función:** Almacena en memoria RAM (`malloc,256m`) las respuestas del backend y las entrega a máxima velocidad, reenviando a Apache solo las peticiones no cacheadas (*MISS*).

---

## 2. Configuración de Varnish

### 2.1. Backend y Cabecera de Depuración (`/etc/varnish/default.vcl`)
Se vinculó Varnish con la IP privada del servidor Apache y se configuró la cabecera `X-Cache` para verificar si las peticiones son servidas desde la memoria (`HIT`) o si viajan al backend (`MISS`):

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

### 2.2. Cambio del Puerto de Escucha a 80
En Debian 13, Varnish corre bajo `Type=exec` en systemd. Para asignarle el puerto 80 manteniendo la compatibilidad, se configuró un override en `/etc/systemd/system/varnish.service.d/override.conf`:

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

---

## 3. Pruebas de Rendimiento con ApacheBench (`ab`)

Se ejecutaron pruebas de estrés con un volumen de **5.000 peticiones** y una concurrencia de **100 usuarios simultáneos**:

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
| **Tiempo Total del Test** | 0.568 s | 0.733 s |
| **Throughput (Requests/sec)** | **8.803,28 #/seg** | **6.821,42 #/seg** |
| **Tiempo Medio por Petición** | 11,359 ms | 14,660 ms |
| **Transfer Rate** | 103.842 KB/s | 81.102 KB/s |
| **Carga en el Servidor Apache** | **5.000 peticiones procesadas** | **1 sola petición (MISS inicial)** |

---

## 4. Visualización con Gnuplot

A partir de los archivos delimitados por tabulaciones (`.tsv`) exportados por el flag `-g` de ApacheBench, se procesaron los tiempos de conexión, espera y tiempo total de respuesta mediante **Gnuplot** (`scripts/generar_grafica.gp`).

![Comparativa de Rendimiento](graphs/comparativa_rendimiento.png)

### Análisis de los Resultados:
1. **Descarga del Servidor Web (*Backend Offloading*):**
   Aunque para un archivo estático pequeño (11 KB) el kernel de Linux y Apache responden con extrema rapidez, la diferencia fundamental reside en el uso de recursos:
   - Con Apache directo, el servidor tuvo que procesar todas y cada una de las 5.000 conexiones.
   - Con Varnish, Apache atendió únicamente la primera petición para almacenar el objeto en memoria; las **4.999 peticiones posteriores se sirvieron 100% desde la RAM de Varnish**, dejando la CPU de Apache libre para peticiones dinámicas.
2. **Impacto de la Concurrencia:**
   Como se observa en la gráfica, tanto Apache como Varnish mantienen una latencia sumamente estable en torno a 10-15 ms, con picos mínimos bien controlados por debajo de los 100 ms bajo una ráfaga masiva de 100 conexiones concurrentes.

---

## 5. Estructura del Repositorio

```text
practica-varnish/
├── configs/
│   ├── default.vcl           # Configuración VCL de Varnish (Backend e inyección de cabeceras)
│   └── override.conf         # Override de systemd para escuchar en el puerto 80
├── data/
│   ├── apache_bench.tsv      # Datos crudos de ApacheBench contra Apache
│   ├── apache_summary.txt    # Resumen de resultados de Apache
│   ├── varnish_bench.tsv     # Datos crudos de ApacheBench contra Varnish
│   └── varnish_summary.txt   # Resumen de resultados de Varnish
├── graphs/
│   └── comparativa_rendimiento.png  # Gráfica generada con Gnuplot
├── scripts/
│   └── generar_grafica.gp    # Script de Gnuplot para generar la gráfica comparativa
└── README.md                 # Documentación técnica de la práctica
```
