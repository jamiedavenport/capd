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
    repo: "cap",
    dir: "docs",
  },
  deployment: {
    site: "https://cap.jxd.dev",
  },
});
