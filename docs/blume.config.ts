import { defineConfig } from "blume";

export default defineConfig({
  title: "Capd",
  description: "Save anything on your Mac and find it again in seconds.",
  logo: { image: "/logo.svg", text: "Capd" },
  content: {
    root: "content",
  },
  github: {
    owner: "jamiedavenport",
    repo: "capd",
    dir: "docs",
  },
  deployment: {
    site: "https://capd.jxd.dev",
  },
});
