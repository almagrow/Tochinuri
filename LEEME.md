# TochiNuri · web

## Qué hay en esta carpeta
- `index.html` — la app completa.
- `config.js` — conexión con la base de datos (Supabase). La clave es pública y segura de compartir.
- `manifest.webmanifest`, `icons/` — para instalarla en el móvil con su icono.
- `sw.js` — para que se abra aunque no haya conexión.
- `netlify.toml` — ajustes de Netlify.
- `supabase/schema.sql` — estructura de la base de datos (ya creada).

## Subir a Netlify
1. Entra en https://app.netlify.com/projects/tochinuri/deploys
2. Arrastra esta carpeta (o el .zip) a la zona «Drag and drop your project folder here».
3. En unos segundos estará en https://tochinuri.netlify.app

Para actualizarla más adelante, repite el paso 2 con la nueva versión.

## Ajustes de Supabase que faltan
En https://supabase.com/dashboard/project/oystbpatrbppgbpeqjqp/auth/url-configuration
- **Site URL**: `https://tochinuri.netlify.app` (o tu dominio cuando lo tengas).
- **Redirect URLs**: añade `https://tochinuri.netlify.app/**` (y tu dominio).
Sin esto, los enlaces de los correos (confirmar cuenta y cambiar contraseña) llevan a una dirección equivocada.

**Correos**: el envío de correos que trae Supabase de serie es solo para pruebas y está muy limitado.
Para que lleguen a cualquier usuario, configura un servicio de correo (SMTP) en
Authentication → Emails → SMTP Settings (por ejemplo Resend o Brevo, que tienen plan gratuito).

## Tu dominio
Cuando lo compres: Netlify → proyecto tochinuri → Domain management → Add a domain.
Después cambia la Site URL de Supabase a tu dominio.
