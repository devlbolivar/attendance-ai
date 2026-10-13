# Congrega

Aplicación mobile-first de asistencia para **Maipú y Cerrillos**. Next.js 16, React 19, TypeScript y Supabase (Postgres, Auth y Edge Functions). Despliegue previsto en Vercel.

## Qué incluye

- **Coordinación**: ambas iglesias, reportes, fichas, correcciones, invitaciones, recuperación asistida de cuentas y auditoría.
- **Encargado de asistencia**: una iglesia, registro, reuniones anteriores pendientes y gestión de fichas. No puede reabrir reuniones cerradas ni cambiar accesos.
- Fecha actual de `America/Santiago`, editable para cargas anteriores; múltiples servicios diarios.
- Lista con búsqueda por nombre, presente/ausente con un toque, contador de pendientes y cierre explícito.
- Cantidad de visitantes; los datos desconocidos del historial se muestran como tales.
- Reportes diarios, semanales (lunes–domingo), mensuales, semestrales (enero–junio / julio–diciembre) y anuales. Vista de ambas iglesias, historial individual, ausencias consecutivas y exportación `.xlsx` con resumen, personas, reuniones y detalle.
- Gestión de variantes de nombre: revisión y unión explícita de fichas de la misma iglesia, con auditoría.

## Desarrollo

```sh
npm ci
cp .env.example .env.local
# Completar las dos variables públicas de Supabase.
npm run dev
```

```sh
npm test
npm run typecheck
npm run build
```

Las exportaciones usan ExcelJS, cargado únicamente al exportar. La sesión se gestiona con Supabase Auth en el navegador. No hay datos personales en el HTML generado por Next.js ni en el repositorio. Todos los accesos a datos dependen de RLS y las escrituras de operaciones autenticadas en Postgres.

## Base de datos

`supabase/schema.sql` documenta el esquema completo para una base vacía. Las migraciones de `supabase/migrations` registran los cambios aplicados. **No ejecutar el esquema inicial de nuevo sobre una base ya configurada.**

Tablas: `churches`, `profiles`, `members`, `meetings`, `attendance`, `audit_log`, `import_notes`. `private.invitations` contiene las autorizaciones para crear cuentas.

- RLS en todas las tablas. Sin lectura de datos anónima.
- Los clientes autenticados solo tienen `SELECT`; escriben por `public.command`.
- `public.command` es un wrapper `SECURITY INVOKER` de una operación privada que valida identidad, perfil activo, rol, iglesia y estado de la reunión. No se aceptan roles de `user_metadata`.
- El trigger de creación de usuarios exige una invitación previa y asigna permisos desde la tabla privada.
- La desactivación se consulta en la base de datos en cada operación, no depende de que expire el JWT.
- Los cambios de miembros, reuniones, asistencias y perfiles se auditan.
- El cierre y el registro adquieren bloqueo de fila sobre la reunión, evitando cambios simultáneos durante el cierre.

`tests/security.sql` verifica permisos en una transacción que termina en `ROLLBACK`. Crea identidades sintéticas solo dentro de esa transacción: no deja cuentas de prueba ni enlaces de acceso.

## Primer acceso

La cuenta inicial se autoriza en `private.invitations` por el administrador del proyecto. Una vez autorizada:

1. En Supabase, **Authentication → Users → Add user → Create new user**.
2. Usar exactamente el correo autorizado, una contraseña elegida por el titular y **Auto Confirm User**, si se ofrece esa opción.
3. Ingresar en la aplicación con ese correo y contraseña.

El titular elige la contraseña directamente en Supabase. No hay endpoint público de bootstrap, contraseña predeterminada ni credencial administrativa en el frontend.

Para otra instalación, autorizar primero el correo desde el SQL Editor (sustituir los valores):

```sql
insert into private.invitations(email,display_name,role,church_id)
values ('titular@example.com','Titular','coordinator',null);
```

Después, Coordinación gestiona las invitaciones desde la aplicación. La función `manage-users` valida el JWT con `getUser` y consulta el perfil activo antes de utilizar Auth Admin. Devuelve enlaces privados de un solo uso para compartir manualmente; **no envía correos**. La clave `service_role` permanece exclusivamente en el entorno de Supabase Edge Functions.

```sh
supabase functions deploy manage-users --project-ref YOUR_PROJECT_REF --no-verify-jwt
```

La validación JWT se realiza dentro de la función para admitir las claves publicables modernas; `--no-verify-jwt` no significa que la operación sea pública. Una llamada sin sesión válida devuelve 401, y una cuenta sin Coordinación devuelve 403.

## Recuperación de contraseña

- El formulario solicita un correo de recuperación a Supabase Auth. Para entregarlo a usuarios reales, configurar **SMTP** y la URL del sitio en Supabase; el servicio de correo de pruebas tiene restricciones.
- Alternativa sin SMTP: otra cuenta de Coordinación genera un enlace desde Gestión. Si solo existe una cuenta y pierde el acceso, el propietario del proyecto puede restablecerla desde Supabase.
- En **Authentication → URL Configuration**, establecer Site URL con el dominio final y permitir la raíz y `/activar` como redirecciones. Las invitaciones generadas en la aplicación usan `/activar#token_hash=…&type=invite` y eliminan el token de la URL antes de seguir.
- La autenticación no permite registro abierto: crear la cuenta exige una autorización en la tabla privada.

## Importación del historial

Los Excel y los resultados de extracción se mantienen fuera de Git. El script necesita Python y `openpyxl` para lectura; no modifica las planillas.

```sh
python scripts/import_workbooks.py /ruta/a/planillas private/import.json 2026-10-13
# Revisar resultados antes de aplicar lotes con scripts/import_sql.py.
```

Reglas acordadas:

1. Solo hojas mensuales de 2026, sin plantillas de impresión.
2. `X`/`x`: presente. Vacío: ausente **solo cuando la columna tiene asistencia registrada**.
3. Columna completamente vacía: sin registro. Guiones sin presentes: culto no realizado. No se contabilizan en porcentajes.
4. Fechas futuras: sin registro. Al disminuir el número de día, la fecha continúa al mes siguiente.
5. Dos columnas dominicales: Escuela dominical y Culto general. Se distinguen por fecha y número de servicio.
6. Una persona solo forma parte del denominador de las reuniones en cuya lista figuraba. No se imputan ausencias antes de su incorporación ni por hojas ausentes.
7. Solo se deduplican nombres iguales tras quitar espacios sobrantes, diferencias de mayúsculas y acentos, dentro de la misma iglesia. Los nombres distintos no se fusionan automáticamente.
8. Los miembros de la última hoja mensual quedan activos. Las fichas que solo aparecen en meses anteriores quedan históricas/inactivas. Las fechas de incorporación y salida inferidas tienen precisión mensual; la lista por reunión es la fuente del historial.
9. No se infieren visitas nuevas cuando no existe un total explícito. En Maipú no hay hoja SEPTIEMBRE: no se inventan registros para cubrir el vacío.
10. Si se repite una fecha entre hojas, prevalece el registro efectivo frente al vacío; dos registros efectivos distintos generan una observación y prevalece la hoja posterior.

## Vercel

Conectar este repositorio, seleccionar Next.js y configurar en producción y preview:

| Variable | Valor |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL del proyecto de Supabase |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Clave **publishable**, nunca `service_role` |

No se requiere una clave administrativa en Vercel. El nombre de la rama de producción inicial es `master`.

La protección de despliegue de Vercel es independiente del login de Congrega. Debe revisarla el propietario si desea que los encargados accedan sin pertenecer al equipo de Vercel. No se retira automáticamente.

## Validación y límites

Se verifican compilación, tipos, reglas de períodos y porcentajes, y seguridad SQL. Las pruebas SQL no sustituyen las pruebas completas del navegador con usuarios reales. La primera cuenta, el proveedor de correo y la publicación final requieren la configuración del propietario cuando no hay acceso autorizado desde la integración.

Excel es una exportación de consulta; no reemplaza un respaldo completo de Postgres. Establecer respaldos periódicos para uso operativo.
