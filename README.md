# Servicios de Red e Internet — RA3: Servidores Web

Repositorio de prácticas de **RA3 (Administración de servidores web)** sobre **Debian 13 (Trixie)** en **Amazon Web Services (AWS)**, cubriendo Apache, Nginx, HAProxy, Varnish Cache, ApacheBench (`ab`), Gnuplot y GoAccess.

---

## Índice de Tareas

| Tarea | Documento | Estado |
| :--- | :--- | :---: |
| **T1. Anatomía de HTTP** *(criterio a)* | [T1 — Anatomía de HTTP](docs/T1-Anatomia-HTTP.md) | 🟡 En progreso *(falta captura Wireshark)* |
| **T2. Apache y Nginx: instalación, módulos, URLs y vhosts** *(b, c, d)* | — | ❌ Pendiente |
| **T3. Autenticación y control de acceso** *(criterio e)* | — | ❌ Pendiente |
| **T4. CA propia y HTTPS endurecido** *(criterios f, g)* | — | ❌ Pendiente |
| **T5. Proxy inverso, balanceo y rendimiento** *(criterios g, h)* | [T5 — Proxy inverso, balanceo y rendimiento](docs/T5-Proxy-Balanceo-Rendimiento.md) | 🟡 Avanzado *(HAProxy + Varnish + `ab` + Gnuplot)* |
| **T6. Logs: estadísticas e incidencias** *(criterio i)* | [T6 — Logs, estadísticas e incidencias](docs/T6-Logs-Estadisticas-Incidencias.md) | 🟡 En progreso *(`mod_remoteip` + GoAccess)* |
| **T7. Documento de servicio** *(criterio j)* | — | ❌ Pendiente |

---

## Estructura del Repositorio

```text
practica-varnish/
├── capturas/                 # Capturas de pantalla organizadas por tarea (T1, T2...)
├── configs/                  # Ficheros de configuración (Varnish, HAProxy, Apache, Nginx)
├── data/                     # Salidas crudas de ApacheBench (.tsv y .txt)
├── docs/                     # Documentación detallada de cada tarea (T1–T7)
├── graphs/                   # Gráficas generadas con Gnuplot
├── scripts/                  # Scripts auxiliares y de Gnuplot
└── README.md                 # Índice general del repositorio
```
