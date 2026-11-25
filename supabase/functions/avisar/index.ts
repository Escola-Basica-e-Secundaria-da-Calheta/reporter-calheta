// Repórter da Calheta · Participa — envia um aviso (Web Push) a todos os aparelhos inscritos.
// Só um professor (public.e_professor()) pode chamar. As chaves VAPID estão em public.segredos.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ erro: "método" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const auth = req.headers.get("Authorization") ?? "";

  const eu = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: prof } = await eu.rpc("e_professor");
  if (prof !== true) return json({ erro: "Só os professores podem enviar avisos." }, 403);

  let corpo: { titulo?: string; texto?: string; url?: string } = {};
  try { corpo = await req.json(); } catch { /* vazio */ }
  const msg = JSON.stringify({
    titulo: String(corpo.titulo ?? "Repórter da Calheta").slice(0, 80),
    texto: String(corpo.texto ?? "").slice(0, 200),
    url: String(corpo.url ?? "").startsWith("https://") ? String(corpo.url).slice(0, 300) : undefined,
  });

  const adm = createClient(url, service);
  const { data: chaves } = await adm.from("segredos").select("chave,valor").in("chave", ["vapid_publica", "vapid_privada"]);
  const k = Object.fromEntries((chaves ?? []).map((x: { chave: string; valor: string }) => [x.chave, x.valor]));
  if (!k.vapid_publica || !k.vapid_privada) return json({ erro: "Faltam as chaves VAPID na base de dados." }, 500);
  webpush.setVapidDetails("mailto:joel.l.cunha@edu.azores.gov.pt", k.vapid_publica, k.vapid_privada);

  const { data: subs } = await adm.from("subscricoes").select("endpoint,dados");
  let enviados = 0;
  const mortos: string[] = [];
  await Promise.all((subs ?? []).map(async (s: { endpoint: string; dados: webpush.PushSubscription }) => {
    try { await webpush.sendNotification(s.dados, msg, { TTL: 60 * 60 * 24 * 3 }); enviados++; }
    catch (e) { const c = (e as { statusCode?: number }).statusCode; if (c === 404 || c === 410) mortos.push(s.endpoint); }
  }));
  if (mortos.length) await adm.from("subscricoes").delete().in("endpoint", mortos);
  return json({ enviados, total: (subs ?? []).length, removidos: mortos.length });
});
