import { defineConfig } from "blume";

export default defineConfig({
  title: "cap",
  description: "An open-source native macOS capture and bookmarking app.",
  logo: { image: "/logo.svg", text: "cap" },
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
