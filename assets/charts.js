"use strict";

document.querySelectorAll("canvas[data-chart-config]").forEach((canvas) => {
    new Chart(canvas, JSON.parse(canvas.dataset.chartConfig));
});
