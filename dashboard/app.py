import os
import sqlite3
import sys
from urllib.parse import parse_qs

import dash_ag_grid as dag
import pandas as pd
import plotly.express as px
from dash import Dash, Input, Output, callback, ctx, dcc, html

# read database path and optional port from command line
DB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050


def query(sql, params=()):
    # open a fresh connection per query for thread safety
    con = sqlite3.connect(DB)
    df = pd.read_sql_query(sql, con, params=params)
    con.close()
    return df


def make_grid(grid_id, df):
    return dag.AgGrid(
        id=grid_id,
        rowData=df.to_dict("records"),
        columnDefs=[{"field": c} for c in df.columns],
        columnSize="sizeToFit",
    )


def runs_page():
    # load runs table using assignment 9 q1.sql
    q1_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "db", "queries", "q1.sql")
    with open(q1_path, "r", encoding="utf-8") as f:
        runs_df = query(f.read())

    links = [
        html.Li(dcc.Link(r, href=f"/results?run={r}"))
        for r in runs_df["run_id"]
    ]

    return [
        html.H1(f"Runs in {os.path.basename(DB)}"),
        html.Ul(links),
        make_grid("runs-table", runs_df),
    ]


def results_page(run_id):
    # fetch samples and synthetic phenotype flags for this run
    samples_df = query(
        """
        SELECT rs.sample_id, rs.condition, rs.library_type,
               s.sex, s.population, s.family, s.phenotype, s.is_synthetic_phenotype
        FROM run_samples rs
        LEFT JOIN samples s ON s.sample_id = rs.sample_id
        WHERE rs.run_id = ?
        ORDER BY rs.sample_id
        """,
        (run_id,),
    )

    # fetch variant sites for this run
    sites_df = query(
        """
        SELECT chrom, pos, ref, alt, qual, filter
        FROM variants
        WHERE run_id = ?
        ORDER BY chrom, pos
        """,
        (run_id,),
    )

    # build three plots using exact question titles and raw values
    fig_filter = px.histogram(
        sites_df,
        x="filter",
        title="How many sites passed, and why did the others fail?",
    )
    fig_qual = px.histogram(
        sites_df,
        x="qual",
        title="How confident are the calls?",
    )
    fig_pos = px.histogram(
        sites_df,
        x="pos",
        title="Where along the region are the sites?",
    )

    return [
        html.H1(f"Results of {run_id}"),
        html.H2("Samples"),
        html.P("Note: Cohort phenotypes shown below are synthetic (simulated), as flagged by is_synthetic_phenotype."),
        make_grid("samples-table", samples_df),
        html.H2("Plots"),
        dcc.Graph(id="plot-filter", figure=fig_filter),
        dcc.Graph(id="plot-qual", figure=fig_qual),
        dcc.Graph(id="plot-position", figure=fig_pos),
        html.H2("Sites"),
        make_grid("sites-table", sites_df),
    ]


app = Dash(__name__, suppress_callback_exceptions=True)

app.layout = [
    dcc.Location(id="url"),
    html.Div(id="page", children=[]),
]


@callback(
    Output("page", "children"),
    Input("url", "pathname"),
    Input("url", "search"),
)
def draw_page(pathname, search):
    # route to results page when /results?run=<id> is opened
    if pathname == "/results" and search:
        parsed = parse_qs(search.lstrip("?"))
        if "run" in parsed and parsed["run"]:
            return results_page(parsed["run"][0])
    return runs_page()


@callback(
    Output("sites-table", "rowData"),
    Input("plot-filter", "clickData"),
    Input("plot-qual", "clickData"),
    Input("plot-position", "clickData"),
    Input("url", "search"),
)
def filter_sites(click_filter, click_qual, click_pos, search):
    # narrow sites-table when a bar or bin is clicked
    if not search:
        return []
    parsed = parse_qs(search.lstrip("?"))
    if "run" not in parsed or not parsed["run"]:
        return []
    run_id = parsed["run"][0]

    sites_df = query(
        """
        SELECT chrom, pos, ref, alt, qual, filter
        FROM variants
        WHERE run_id = ?
        ORDER BY chrom, pos
        """,
        (run_id,),
    )

    triggered = ctx.triggered_id

    if triggered == "plot-filter" and click_filter and click_filter.get("points"):
        pt = click_filter["points"][0]
        val = pt.get("label") if pt.get("label") is not None else pt.get("x")
        if val is not None:
            filtered = sites_df[sites_df["filter"].astype(str) == str(val)]
            return filtered.to_dict("records")

    if triggered == "plot-qual" and click_qual and click_qual.get("points"):
        pt = click_qual["points"][0]
        if "x0" in pt and "x1" in pt:
            q_num = pd.to_numeric(sites_df["qual"], errors="coerce")
            filtered = sites_df[(q_num >= float(pt["x0"])) & (q_num <= float(pt["x1"]))]
            return filtered.to_dict("records")
        val = pt.get("x")
        if val is not None:
            q_num = pd.to_numeric(sites_df["qual"], errors="coerce")
            filtered = sites_df[q_num == float(val)]
            return filtered.to_dict("records")

    if triggered == "plot-position" and click_pos and click_pos.get("points"):
        pt = click_pos["points"][0]
        if "x0" in pt and "x1" in pt:
            p_num = pd.to_numeric(sites_df["pos"], errors="coerce")
            filtered = sites_df[(p_num >= float(pt["x0"])) & (p_num <= float(pt["x1"]))]
            return filtered.to_dict("records")
        val = pt.get("x")
        if val is not None:
            p_num = pd.to_numeric(sites_df["pos"], errors="coerce")
            filtered = sites_df[p_num == float(val)]
            return filtered.to_dict("records")

    return sites_df.to_dict("records")


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
