const data = new URL(location.href).searchParams.get("data");
document.querySelector("#result").textContent = JSON.stringify(
  JSON.parse(data ?? "{}"),
  null,
  2
);
