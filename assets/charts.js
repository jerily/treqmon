"use strict";

document.querySelectorAll("canvas[data-chart-config]").forEach((canvas) => {
    const style = getComputedStyle(canvas);
    const config = JSON.parse(canvas.dataset.chartConfig);
    const color = style.getPropertyValue("--treqmon-chart-color").trim();
    const fill = style.getPropertyValue("--treqmon-chart-fill").trim();
    config.options.color = style.color;
    config.options.font = { family: style.fontFamily };
    config.data.datasets.forEach((dataset) => {
        if (color) dataset.borderColor = color;
        if (fill) dataset.backgroundColor = fill;
    });
    new Chart(canvas, config);
});
