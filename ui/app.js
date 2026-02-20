(function () {
  const e = React.createElement;
  const useState = React.useState;
  const useEffect = React.useEffect;
  const useRef = React.useRef;

  function buildChart(canvas, label, color) {
    return new Chart(canvas, {
      type: "line",
      data: { labels: [], datasets: [{ label, data: [], borderColor: color, tension: 0.25, pointRadius: 0 }] },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: { x: { display: false }, y: { ticks: { maxTicksLimit: 4 } } },
        plugins: { legend: { display: false } },
      },
    });
  }

  async function api(path, init) {
    const resp = await fetch("/api/" + path.replace(/^\//, ""), init);
    if (!resp.ok) throw new Error(await resp.text());
    return resp.json();
  }

  function App() {
    const [state, setState] = useState(null);
    const [incidents, setIncidents] = useState([]);
    const [selectedIncident, setSelectedIncident] = useState("");
    const [diagnosis, setDiagnosis] = useState(null);
    const [statusMsg, setStatusMsg] = useState("Loading...");

    const qpsRef = useRef(null);
    const ttftRef = useRef(null);
    const latRef = useRef(null);
    const gpuRef = useRef(null);
    const charts = useRef({});

    const refreshAll = async () => {
      try {
        const s = await api("state");
        const inc = await api("incidents");
        setState(s);
        setIncidents(inc.active || []);
        if ((inc.active || []).length > 0 && !selectedIncident) {
          setSelectedIncident(inc.active[0].id);
        }
        setStatusMsg("Updated: " + new Date().toLocaleTimeString());
      } catch (err) {
        setStatusMsg("Error: " + err.message);
      }
    };

    const fetchDiagnosis = async (id) => {
      if (!id) return;
      try {
        const d = await api("diagnosis/" + id);
        setDiagnosis(d);
      } catch (err) {
        setDiagnosis({ narrative: "Diagnosis unavailable: " + err.message });
      }
    };

    const actionFix = async (type) => {
      try {
        await api("fix/" + type, { method: "POST", headers: { "Content-Type": "application/json" } });
        setStatusMsg(type === "apply" ? "Applied fix (balanced routing)" : "Rollback applied (re-introduced skew)");
        await refreshAll();
      } catch (err) {
        setStatusMsg("Action failed: " + err.message);
      }
    };

    useEffect(() => {
      charts.current.qps = buildChart(qpsRef.current, "QPS", "#0f766e");
      charts.current.ttft = buildChart(ttftRef.current, "TTFT p95", "#b45309");
      charts.current.lat = buildChart(latRef.current, "Latency p95", "#7c3aed");
      charts.current.gpu = buildChart(gpuRef.current, "Max GPU util", "#b91c1c");
      return () => Object.values(charts.current).forEach((c) => c && c.destroy());
    }, []);

    useEffect(() => {
      refreshAll();
      const t = setInterval(refreshAll, 3000);
      return () => clearInterval(t);
    }, []);

    useEffect(() => {
      fetchDiagnosis(selectedIncident);
    }, [selectedIncident]);

    useEffect(() => {
      if (!state || !state.global || !charts.current.qps) return;
      const labels = charts.current.qps.data.labels;
      labels.push(new Date().toLocaleTimeString());
      if (labels.length > 30) labels.shift();

      const g = state.global || {};
      const maxGpu = Math.max(0, ...(state.replicas || []).map((r) => Number(r.gpu_util || 0)));
      const points = [
        ["qps", Number(g.qps || 0)],
        ["ttft", Number(g.ttft_p95_ms || 0)],
        ["lat", Number(g.latency_p95_ms || 0)],
        ["gpu", maxGpu],
      ];
      for (const [key, val] of points) {
        const d = charts.current[key].data.datasets[0].data;
        d.push(val);
        if (d.length > 30) d.shift();
        charts.current[key].update("none");
      }
    }, [state]);

    const incidentBadgeClass = incidents.length > 0 ? "pill bad" : "pill ok";
    const diagnosisHtml = diagnosis ? marked.parse(diagnosis.narrative || "") : "<p>Select an incident to view diagnosis.</p>";

    return e("div", { className: "app" }, [
      e("div", { className: "header", key: "h" }, [
        e("div", { key: "l" }, [
          e("h1", { className: "title", key: "t" }, "LATCH Minimal Dashboard"),
          e("p", { className: "subtitle", key: "s" }, "status -> incident -> diagnosis -> fix -> improvement"),
        ]),
        e("div", { key: "r" }, [
          e("span", { className: incidentBadgeClass, key: "i" }, incidents.length > 0 ? "INCIDENT" : "HEALTHY"),
        ]),
      ]),
      e("div", { className: "status", key: "st" }, statusMsg),
      e("div", { className: "grid", key: "g" }, [
        e("section", { className: "card charts", key: "c" }, [
          e("h3", { key: "ct" }, "Live Metrics"),
          e("div", { className: "mini-grid", key: "cg" }, [
            e("div", { className: "chart-wrap", key: "qps" }, [e("p", { className: "chart-title", key: "t" }, "Global QPS"), e("canvas", { ref: qpsRef, height: 120, key: "cv" })]),
            e("div", { className: "chart-wrap", key: "ttft" }, [e("p", { className: "chart-title", key: "t" }, "TTFT p95 (ms)"), e("canvas", { ref: ttftRef, height: 120, key: "cv" })]),
            e("div", { className: "chart-wrap", key: "lat" }, [e("p", { className: "chart-title", key: "t" }, "Latency p95 (ms)"), e("canvas", { ref: latRef, height: 120, key: "cv" })]),
            e("div", { className: "chart-wrap", key: "gpu" }, [e("p", { className: "chart-title", key: "t" }, "Max GPU Util (%)"), e("canvas", { ref: gpuRef, height: 120, key: "cv" })]),
          ]),
        ]),
        e("section", { className: "card incidents", key: "i" }, [
          e("h3", { key: "it" }, "Incidents"),
          e("ul", { className: "list", key: "il" },
            incidents.length === 0
              ? [e("li", { key: "none" }, "No active incidents.")]
              : incidents.map((inc) =>
                  e("li", {
                    className: "incident" + (selectedIncident === inc.id ? " active" : ""),
                    key: inc.id,
                    onClick: () => setSelectedIncident(inc.id),
                  }, [
                    e("div", { key: "a" }, inc.id),
                    e("div", { key: "b" }, inc.type + " / " + inc.severity),
                    e("div", { className: "status", key: "c" }, inc.started_at),
                  ]),
                ),
          ),
        ]),
        e("section", { className: "card diagnosis", key: "d" }, [
          e("h3", { key: "dt" }, "Diagnosis"),
          e("div", { className: "markdown", key: "db", dangerouslySetInnerHTML: { __html: diagnosisHtml } }),
        ]),
        e("section", { className: "card actions", key: "a" }, [
          e("h3", { key: "at" }, "Actions"),
          e("button", { className: "apply", onClick: () => actionFix("apply"), key: "ap" }, "Apply Fix"),
          e("button", { className: "rollback", onClick: () => actionFix("rollback"), key: "rb" }, "Rollback"),
          e("button", { className: "refresh", onClick: refreshAll, key: "rf" }, "Refresh"),
          e("p", { className: "status", key: "as" }, "Apply Fix restores all pods to llm-d serving. Rollback re-introduces skew."),
        ]),
      ]),
    ]);
  }

  ReactDOM.createRoot(document.getElementById("root")).render(e(App));
})();
