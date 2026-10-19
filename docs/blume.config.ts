import { defineConfig } from "blume";

const openPanelClientId = "55bb3bb9-1d42-46fb-ac7b-5ab568269397";

const openPanelInit = `window.op=window.op||function(){var n=[];return new Proxy(function(){arguments.length&&n.push([].slice.call(arguments))},{get:function(t,r){return"q"===r?n:function(){n.push([r].concat([].slice.call(arguments)))}},has:function(t,r){return"q"===r}})}();
window.op("init",{clientId:${JSON.stringify(openPanelClientId)},trackScreenViews:true,trackOutgoingLinks:true,trackAttributes:true});`;

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
  analytics: openPanelClientId
    ? {
        scripts: [
          { content: openPanelInit },
          { src: "https://openpanel.dev/op1.js", strategy: "async" },
        ],
      }
    : undefined,
});
