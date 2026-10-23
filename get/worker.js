const RELEASES = "https://github.com/flatrun/installer/releases/latest/download";

export default {
  fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === "/") {
      return Response.redirect("https://flatrun.dev/install", 302);
    }
    return Response.redirect(RELEASES + pathname, 302);
  },
};
