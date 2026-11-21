import {z} from "zod";
export const uuid=z.string().uuid();
export const acceptedPaymentMethods=["pix","cartao_credito","cartao_debito","dinheiro","vale_refeicao"] as const;
export const defaultPaymentMethods=["pix","cartao_credito","cartao_debito","dinheiro"] as const;
export const paymentMethods=[...acceptedPaymentMethods,"cartao"] as const;
export type PaymentMethod=typeof paymentMethods[number];
export const paymentLabels:Record<PaymentMethod,string>={pix:"Pix",cartao_credito:"Cartão de crédito",cartao_debito:"Cartão de débito",dinheiro:"Dinheiro",vale_refeicao:"Vale-refeição",cartao:"Cartão (crédito ou débito)"};
export const acceptedPaymentsSchema=z.array(z.enum(acceptedPaymentMethods)).min(1,"Selecione ao menos uma forma de pagamento").max(5).refine(v=>new Set(v).size===v.length,"Formas de pagamento duplicadas");
export function paymentLabel(value:string){return paymentLabels[value as PaymentMethod]??value}
export const money=(cents:number)=>new Intl.NumberFormat("pt-BR",{style:"currency",currency:"BRL"}).format(cents/100);
export const date=(value:string)=>new Intl.DateTimeFormat("pt-BR",{dateStyle:"short",timeStyle:"short",timeZone:"America/Sao_Paulo"}).format(new Date(value));
export function parseMoney(input:string){
 const normalized=input.trim().replace(",",".");
 if(!/^\d{1,6}(\.\d{1,2})?$/.test(normalized))throw new Error("Valor monetário inválido");
 const [whole,fraction=""]=normalized.split(".");
 return Number(whole)*100+Number(fraction.padEnd(2,"0"));
}
export const checkoutSchema=z.object({
 slug:z.string().regex(/^[a-z0-9][a-z0-9-]{2,49}$/),request_id:uuid,
 mode:z.enum(["delivery","retirada","mesa"]),name:z.string().trim().min(2).max(100),
 phone:z.string().regex(/^\d{10,13}$/),address:z.string().max(400).optional(),
 notes:z.string().max(500).optional(),table:uuid.optional(),coupon:z.string().trim().max(24).optional(),
 payment:z.enum(paymentMethods),
 items:z.array(z.object({product_id:uuid,quantity:z.number().int().min(1).max(50),addons:z.array(uuid).max(10).refine(a=>new Set(a).size===a.length,"Adicionais duplicados")})).min(1).max(30)
}).superRefine((val,ctx)=>{
 if(val.mode==="delivery"&&(!val.address||val.address.trim().length<10))ctx.addIssue({code:"custom",path:["address"],message:"Informe o endereço completo."});
 if(val.mode==="mesa"&&!val.table)ctx.addIssue({code:"custom",path:["table"],message:"QR Code da mesa inválido."});
});
export type Checkout=z.infer<typeof checkoutSchema>;
export type Role="owner"|"manager"|"kitchen"|"attendant";
export const statuses={pendente:"Pendente",confirmado:"Confirmado",preparando:"Em preparo",pronto:"Pronto",em_entrega:"Em entrega",concluido:"Concluído",cancelado:"Cancelado"} as const;
export type Status=keyof typeof statuses;
export function transitions(status:Status,mode:string,role:Role):Status[]{
 const manage=role!=="kitchen";
 const options:Status[]=[];
 if(status==="pendente"&&manage)options.push("confirmado");
 if(status==="confirmado")options.push("preparando");
 if(status==="preparando")options.push("pronto");
 if(status==="pronto"&&manage)options.push(mode==="delivery"?"em_entrega":"concluido");
 if(status==="em_entrega"&&manage)options.push("concluido");
 if(["pendente","confirmado","preparando","pronto"].includes(status)&&["owner","manager"].includes(role))options.push("cancelado");
 return options;
}
export function csvCell(value:unknown){
 let s=String(value??"");
 if(/^\s*[=+\-@\t\r]/.test(s))s="'"+s;
 return '"'+s.replaceAll('"','""')+'"';
}
export const roleLabels={owner:"Proprietário",manager:"Gerente",kitchen:"Cozinha",attendant:"Atendente"};
export type Addon={id:string;name:string;price:number};
export type Product={id:string;name:string;description:string;price:number;image_url:string|null;addons:Addon[]};
export type PublicMenu={name:string;slug:string;whatsapp:string|null;address:string|null;description?:string;opening_hours?:string;payment_methods?:PaymentMethod[];table_enabled?:boolean;coupons_enabled?:boolean;accepting_orders:boolean;delivery_enabled:boolean;pickup_enabled:boolean;delivery_fee:number;categories:{id:string;name:string;products:Product[]}[]};
