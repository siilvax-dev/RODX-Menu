import Link from "next/link";
export function Brand({dark=false}:{dark?:boolean}){return <Link href="/" className={"brand-lockup"+(dark?" brand-dark":"")} aria-label="RODX Menu — Built for Business."><span className="brand-mark"><img src="/rodx-logo-oficial.png" alt="RODX — Built for Business." /></span><span className="brand-product">MENU</span></Link>}
