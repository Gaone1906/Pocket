import * as store from "./store.js";

export async function askAI(body) {
  try {
    return await store.fn("fabula-ai", body);
  } catch (e) {
    console.warn("fabula-ai failed", body.action, e && e.message);
    throw e;
  }
}
