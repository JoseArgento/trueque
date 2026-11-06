# Changelog

## 0.1.0 (2026-11-05)

Primera versión, para WoW Forever 1.60.1 (interfaz 16001).

- Tablón de guild con avisos de tres tipos: Quiero, Tengo, Puedo hacer. Ítem o receta por Shift-clic, cantidad, nota, vencimiento a los 7 días (`/trueque dias N`), hasta 20 avisos por jugador.
- Sincronizado por mensajes de addon en el canal de guild (prefijo `Trueque1`): pregunta al entrar y al abrir el tablón, cada uno responde con sus avisos, y los cambios viajan al momento. Nada de lo recibido se ejecuta; solo el autor puede cerrar o cambiar un aviso.
- "Lo tengo" y "Me interesa" susurran al autor una línea ya escrita, solo desde el clic.
- Cruces: etiqueta "hay uno" y aviso en el chat (una vez) cuando alguien tiene o puede hacer lo que buscás, o busca lo que ofrecés.
- Con Taller: "Publicar lo que me falta" publica un Quiero por cada material de la lista de compras.
- Libro de pergamino (piel Pergamino 5) con dos marcadores, botón del minimapa, atajo de teclado, compartimento de addons, idioma elegible y `/trueque errores` con los errores propios para copiar.
- Después de probarlo en el cliente (6/11): la lista va con los más nuevos arriba y los campos se vacían al publicar; el buscador en su propia fila; el aviso de "sin guild" ya no se dibuja sobre la lista; la cantidad puede quedar vacía (sin límite); un aviso propio se cambia con un clic (mismo id y fecha, la guild lo recibe de nuevo) y se cierra solo desde "Ya está" o el clic derecho, con pregunta; tooltip del juego al pasar por un ítem o receta y Shift-clic para pegarlo en el chat; el detalle muestra Cantidad, Nota y Vence en filas.
