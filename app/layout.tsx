import type { Metadata, Viewport } from 'next';
import './globals.css';
export const metadata: Metadata = {title:'Congrega · Asistencia',description:'Cada persona cuenta. Registro de asistencia de Maipú y Cerrillos.',robots:{index:false,follow:false}};
export const viewport: Viewport = {width:'device-width',initialScale:1,themeColor:'#124b45'};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="es"><body>{children}</body></html>}
