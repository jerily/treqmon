const fs = require("node:fs");
const path = require("node:path");
const root = __dirname;
for (const dir of ["js", "css"]) fs.mkdirSync(path.join(root, "public", dir), {recursive: true});
for (const [source, target] of [
    ["node_modules/chart.js/dist/chart.umd.js", "public/js/chart.umd.js"],
    ["../assets/charts.js", "public/js/charts.js"],
    ["../assets/charts.css", "public/css/charts.css"],
]) fs.copyFileSync(path.join(root, source), path.join(root, target));
