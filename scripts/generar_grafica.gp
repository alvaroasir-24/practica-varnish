# Indicar que el separador es el tabulador (\t) para no confundirse con los espacios de la fecha
set datafile separator "\t"

# Configuración de salida de la imagen
set terminal pngcairo size 1024,650 enhanced font "Arial,11"
set output 'graphs/comparativa_rendimiento.png'

# Títulos y ejes
set title "Comparativa de Rendimiento: Apache Directo vs Varnish Cache\n(5.000 peticiones con Concurrencia 100)" font "Arial-Bold,13"
set xlabel "Número de Petición"
set ylabel "Tiempo Total de Respuesta - ttime (milisegundos)"
set grid
set key top right box

# Graficar la columna 5 (ttime en milisegundos)
plot "data/apache_bench.tsv" every ::1 using 5 with lines lc rgb "#E41A1C" lw 1 title "Apache Directo (Sin Varnish)", \
     "data/varnish_bench.tsv" every ::1 using 5 with lines lc rgb "#377EB8" lw 1 title "Varnish Cache"
