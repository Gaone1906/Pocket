const given = globalThis.FABULA_PROFILE || {};

export const P = {
  who: given.who || "pranav",
  user: given.user || "00000000-0000-0000-0000-000000000000",
  pre: given.pre || "ortus",
  name: given.name || "Fabula",
  store: given.store || "fabula",
  guided: !!given.guided,
  nick: given.nick || "",
  welcome: given.welcome || "",
};

export function lk(name) {
  return `${P.store}.${name}`;
}
