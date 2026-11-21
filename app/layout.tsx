import "./globals.css";
import type {Metadata} from "next";
export const metadata:Metadata={title:"RODX Menu — Gestão gastronômica",description:"Cardápios digitais, pedidos e operação em um único lugar."};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="pt-BR"><body>{children}</body></html>}
