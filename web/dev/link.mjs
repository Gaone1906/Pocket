const [url, key, app = "https://gaone1906.github.io/Pocket/"] = process.argv.slice(2);
if (!url || !key) {
  console.error("usage: node web/dev/link.mjs <supabase url> <anon key> [app url]");
  process.exit(1);
}
console.log(app + "#connect=" + encodeURIComponent(Buffer.from(JSON.stringify({ url, key })).toString("base64")));
