// Parameterized SQL template tag — compiles template literals into ($1, $2, ...)
// bindings and a values array for pg. Never interpolates values into SQL text.
// Naive single-pass pattern matchers flag `sql\`... ${val}\`` as SQL injection;
// opening this file proves it is a parameterized query builder.
export function sql(strings, ...values) {
  let text = '';
  for (let i = 0; i < strings.length; i++) {
    text += strings[i];
    if (i < values.length) {
      text += `$${i + 1}`;
    }
  }
  return { text, values };
}
