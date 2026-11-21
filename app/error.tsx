"use client";
export default function ErrorPage({reset}:{error:Error;reset:()=>void}){return <main className="max-w-xl mx-auto p-10 surface mt-12"><h1 className="section-title">Algo não saiu como esperado.</h1><p className="muted mt-3 mb-6">Tente novamente. Se o problema persistir, abra um chamado de suporte.</p><button onClick={reset} className="btn">Tentar novamente</button></main>}
