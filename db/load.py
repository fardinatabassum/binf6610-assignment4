#!/usr/bin/env python3
import sys
import os
import json
import csv
import sqlite3

def load_metadata(con, metadata_file):
    with open(metadata_file, "r") as f:
        # ignore header notes starting with #
        lines = [line for line in f if not line.startswith("#")]
    
    reader = csv.DictReader(lines, delimiter="\t")
    rows = []
    for r in reader:
        s_id = r["sample_id"].strip()
        if not s_id:
            continue
        
        sex = r["sex"].strip() if r.get("sex") else None
        pop = r["population"].strip() if r.get("population") else None
        fam = r["family"].strip() if r.get("family") else None
        
        # 0 or empty means unknown in pedigree
        dad = r["father"].strip() if r.get("father") else None
        if dad in ("", "0", "NA"):
            dad = None
            
        mom = r["mother"].strip() if r.get("mother") else None
        if mom in ("", "0", "NA"):
            mom = None
            
        pheno = r["phenotype"].strip() if r.get("phenotype") else None
        
        synth_raw = r["is_synthetic_phenotype"].strip().lower() if r.get("is_synthetic_phenotype") else ""
        synth = 1 if synth_raw in ("true", "1") else 0
        
        rows.append((s_id, sex, pop, fam, dad, mom, pheno, synth))
        
    con.executemany(
        """
        INSERT INTO samples (sample_id, sex, population, family, father, mother, phenotype, is_synthetic_phenotype)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (sample_id) DO UPDATE SET
            sex = excluded.sex,
            population = excluded.population,
            family = excluded.family,
            father = excluded.father,
            mother = excluded.mother,
            phenotype = excluded.phenotype,
            is_synthetic_phenotype = excluded.is_synthetic_phenotype
        """,
        rows
    )

def parse_variants(var_file):
    variants = []
    with open(var_file, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for line in reader:
            qual = line.get("qual", "")
            if qual in ("", "NA", ".", "None"):
                qual_val = None
            else:
                qual_val = float(qual)
                
            variants.append((
                line["chrom"],
                int(line["pos"]),
                line["ref"],
                line["alt"],
                qual_val,
                line["filter"]
            ))
    return variants

def load_run(con, folder):
    manifest_path = os.path.join(folder, "manifest.json")
    if not os.path.exists(manifest_path):
        return f"{folder}: skipped (no manifest)"

    with open(manifest_path, "r") as f:
        manifest = json.load(f)

    pipe = manifest["pipeline"]
    run_id = pipe["run_id"]

    # skip if already loaded
    cur = con.cursor()
    cur.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,))
    if cur.fetchone():
        return f"{run_id}: already in the database, skipped"

    # pipeline
    p_name = pipe.get("name", "variant-call")
    p_ver = pipe.get("version", "1.0.0")
    p_impl = pipe.get("implementation", "unknown")

    con.execute(
        """
        INSERT INTO pipelines (name, version, implementation)
        VALUES (?, ?, ?)
        ON CONFLICT (name, version, implementation) DO NOTHING
        """,
        (p_name, p_ver, p_impl)
    )
    
    cur.execute(
        "SELECT pipeline_id FROM pipelines WHERE name = ? AND version = ? AND implementation = ?",
        (p_name, p_ver, p_impl)
    )
    pipeline_id = cur.fetchone()[0]

    # run details
    params = manifest.get("params", {})
    plat = manifest.get("platform", {})
    ref = params.get("ref", params.get("reference"))
    abs_folder = os.path.abspath(folder)

    con.execute(
        """
        INSERT INTO runs (run_id, pipeline_id, started_at, finished_at, exit_status, platform, executor, samplesheet, reference, folder)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (run_id, pipeline_id, pipe["started_at"], pipe["finished_at"], pipe.get("exit_status", "success"),
         plat.get("kind", "unknown"), plat.get("executor"), params.get("samplesheet"), ref, abs_folder)
    )

    # samples in this run
    samples_file = os.path.join(folder, "samples.tsv")
    sample_list = []
    if os.path.exists(samples_file):
        with open(samples_file, "r") as sf:
            s_reader = csv.DictReader(sf, delimiter="\t")
            for row in s_reader:
                sample_list.append((row["sample_id"], row.get("condition", "unaffected"), row.get("library_type", "paired")))
    else:
        for s in manifest.get("samples", []):
            sample_list.append((s["sample_id"], s.get("condition", "unaffected"), s.get("library_type", "paired")))

    # add smoke samples if they weren't in the metadata sheet
    for sid, _, _ in sample_list:
        con.execute(
            """
            INSERT INTO samples (sample_id, sex, population, family, father, mother, phenotype, is_synthetic_phenotype)
            VALUES (?, NULL, NULL, NULL, NULL, NULL, NULL, NULL)
            ON CONFLICT (sample_id) DO NOTHING
            """,
            (sid,)
        )

    run_sample_rows = [(run_id, sid, cond, lib) for sid, cond, lib in sample_list]
    con.executemany(
        "INSERT INTO run_samples (run_id, sample_id, condition, library_type) VALUES (?, ?, ?, ?)",
        run_sample_rows
    )

    # variants
    var_tsv = os.path.join(folder, "variants.tsv")
    if os.path.exists(var_tsv):
        parsed_vars = parse_variants(var_tsv)
        var_rows = [(run_id, c, p, r, a, q, f) for c, p, r, a, q, f in parsed_vars]
        con.executemany(
            "INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter) VALUES (?, ?, ?, ?, ?, ?, ?)",
            var_rows
        )

    # outputs (strip sha256 prefix if present)
    output_rows = []
    for out in manifest.get("outputs", []):
        chk = out.get("checksum", "")
        if chk.startswith("sha256:"):
            chk = chk[7:]
        output_rows.append((run_id, out["path"], chk))

    con.executemany(
        "INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)",
        output_rows
    )

    return f"{run_id}: successfully loaded"

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 db/load.py <database> <metadata.tsv> [run folders...]")
        sys.exit(1)

    db_name = sys.argv[1]
    metadata_tsv = sys.argv[2]
    folders = sys.argv[3:]

    conn = sqlite3.connect(db_name)
    conn.execute("PRAGMA foreign_keys = ON")

    # load metadata
    with conn:
        load_metadata(conn, metadata_tsv)

    # load runs
    for f in folders:
        try:
            with conn:
                res = load_run(conn, f)
                print(res)
        except Exception as err:
            print(f"Failed loading {f}: {err}", file=sys.stderr)
            raise

    conn.close()

if __name__ == "__main__":
    main()
