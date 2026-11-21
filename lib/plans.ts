export type PaidPlan="essencial"|"pro"|"premium";
export type PlanLevel=1|2|3;
export type Plan={id:PaidPlan;name:string;price:number;level:PlanLevel;headline:string;description:string;recommended?:boolean;benefits:string[]};
export const plans:Plan[]=[
 {id:"essencial",name:"Essencial",price:4990,level:1,headline:"Comece a vender pelo digital",description:"Para pequenos estabelecimentos que precisam de um cardápio profissional e pedidos organizados.",benefits:["Cardápio digital com perfil e link exclusivo","Produtos, categorias, adicionais e estoque","Pedidos de delivery e retirada","Formas de pagamento personalizadas","Contato pelo WhatsApp","Painel de pedidos e indicadores básicos","Suporte por chamados"]},
 {id:"pro",name:"Pro",price:9990,level:2,headline:"Organize a operação inteira",description:"Para restaurantes que atendem no salão, balcão e delivery com controle de caixa e equipe.",recommended:true,benefits:["Tudo do Essencial","PDV com carrinho, produtos e estoque","Caixa: abertura, recebimentos, sangria e fechamento","Histórico de clientes","Mesas com QR Code e contas por mesa","Painel de cozinha em tempo real","Cadastro e despacho de entregadores próprios","Cupons de desconto e promoções","Equipe com permissões por função"]},
 {id:"premium",name:"Premium",price:14990,level:3,headline:"Tome decisões e fidelize clientes",description:"Para operações que querem acompanhar resultados, estimular novas compras e crescer com dados.",benefits:["Tudo do Pro","Fidelidade por pontos de pedidos concluídos","Painel de pontuação de clientes","Relatórios de vendas dos últimos 30 dias","Exportação de pedidos em CSV","Indicadores de faturamento, ticket e modalidade"]}
];
export const comparison=[
 {name:"Cardápio digital, perfil e produtos",level:1},
 {name:"Delivery, retirada e gestão de pedidos",level:1},
 {name:"Formas de pagamento e contato WhatsApp",level:1},
 {name:"Controle de estoque e indicadores básicos",level:1},
 {name:"Suporte por chamados",level:1},
 {name:"Mesas e QR Code para pedidos",level:2},
 {name:"Painel de cozinha dedicado",level:2},
 {name:"Cupons e promoções",level:2},
 {name:"Gestão de equipe e permissões",level:2},
 {name:"PDV · venda presencial e pedidos manuais",level:2},
 {name:"Caixa e controle de recebimentos",level:2},
 {name:"Histórico de clientes e contato",level:2},
 {name:"Equipe própria de entregas e despacho",level:2},
 {name:"Contas e consumo por mesa",level:2},
 {name:"Fidelidade por pontos",level:3},
 {name:"Relatórios e exportação CSV",level:3}
] as const;
const limits:Record<string,PlanLevel>={mesas:2,cupons:2,cozinha:2,equipe:2,pdv:2,caixa:2,clientes:2,entregas:2,entregadores:2,salao:2,relatorios:3,fidelidade:3};
export function requiredLevel(module:string):PlanLevel{return limits[module]??1}
export function canUseModule(module:string,level:number){return level>=requiredLevel(module)}
export function upgradePlan(module:string){return plans.find(plan=>plan.level===requiredLevel(module))??plans[0]}
