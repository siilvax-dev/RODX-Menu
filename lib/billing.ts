import "server-only";
import Stripe from "stripe";
import {resolvePrice,billingSetup} from "./billing-config";
export function stripe(){if(!process.env.STRIPE_SECRET_KEY)throw new Error("Stripe não configurado");return new Stripe(process.env.STRIPE_SECRET_KEY)}
export function planPrice(plan:string){return resolvePrice(plan,process.env)}
export function pricePlan(price:string){return price?(["essencial","pro","premium"] as const).find(p=>planPrice(p)===price)??null:null}
export function billingStatus(){return billingSetup(process.env)}
export function appUrl(){return process.env.APP_URL||"http://localhost:3000"}
