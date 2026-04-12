#!/usr/bin/env python3
"""
build_db.py — Processes the Artdatabanken/Dyntaxa CSV files into a
single SQLite database (taxa.db) bundled with the BirdTally app.

Usage:
    python3 scripts/build_db.py

Output:
    assets/data/taxa.db

Source CSVs (in csv/):
    Alla_arter_underarter_komplex_hybrider_Sverige.csv  — master index
    Alla_arter_Sverige_forekommande.csv                 — browse list
    Alla_rödlistade_sverige.csv                         — red list badges
    Fageldirektivsarter_bilaga_1.csv                    — Birds Directive Annex I
    Skogsvardslagen_prio_arter.csv                      — Forestry law priority
"""

import csv
import sqlite3
import os
import sys

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
CSV_DIR = os.path.join(ROOT, "csv")
OUT_DB = os.path.join(ROOT, "assets", "data", "taxa.db")

CSV_MASTER = os.path.join(CSV_DIR, "Alla_arter_underarter_komplex_hybrider_Sverige.csv")
CSV_BROWSE = os.path.join(CSV_DIR, "Alla_arter_Sverige_forekommande.csv")
CSV_REDLIST = os.path.join(CSV_DIR, "Alla_rödlistade_sverige.csv")
CSV_BIRDS_DIR = os.path.join(CSV_DIR, "Fageldirektivsarter_bilaga_1.csv")
CSV_FORESTRY = os.path.join(CSV_DIR, "Skogsvardslagen_prio_arter.csv")

# ---------------------------------------------------------------------------
# Categories included in the app (everything else is discarded)
# ---------------------------------------------------------------------------
INCLUDED_CATEGORIES = {"Art", "Underart", "Hybrid", "Artkomplex", "Kollektivtaxon", "Pseudotaxon"}

# Categories shown in the browse list (Artlistan)
BROWSE_CATEGORIES = {"Art", "Underart"}

# Red list categories allowed in the browse list
BROWSE_REDLIST_OK = {"LC", "LC°", "NT", "NT°", "VU", "EN", "CR", "CR°"}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def read_csv(path):
    """Read a semicolon-delimited CSV with UTF-8 BOM, return list of dicts."""
    with open(path, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f, delimiter=";"))


def parse_int(s):
    try:
        return int(s.strip()) if s and s.strip() else None
    except ValueError:
        return None


def first_two_words(scientific_name):
    """Return the genus + species part of a scientific name (first two words)."""
    parts = scientific_name.strip().split()
    if len(parts) >= 2:
        return f"{parts[0]} {parts[1]}"
    return scientific_name.strip()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Reading CSVs...")

    master_rows = read_csv(CSV_MASTER)
    browse_rows = read_csv(CSV_BROWSE)
    redlist_rows = read_csv(CSV_REDLIST)
    birds_dir_rows = read_csv(CSV_BIRDS_DIR)
    forestry_rows = read_csv(CSV_FORESTRY)

    # -- Build badge sets (taxon_id → flag) ----------------------------------

    # Red list: use the master file's RedListCategory column (most complete).
    # We also cross-reference the dedicated red list file for CR/EN/VU/NT/DD.
    redlist_ids = {int(r["Taxon id"]) for r in redlist_rows if r.get("Taxon id")}

    birds_dir_ids = {int(r["Taxon id"]) for r in birds_dir_rows if r.get("Taxon id")}
    forestry_ids = {int(r["Taxon id"]) for r in forestry_rows if r.get("Taxon id")}

    # Browse list: taxon_ids from forekommande that are Art or Underart with
    # an acceptable red list category. Population excluded.
    browse_ids = set()
    for r in browse_rows:
        cat = r.get("Kategori", "").strip()
        rl = r.get("RedListCategory", "").strip()
        if cat in BROWSE_CATEGORIES and rl in BROWSE_REDLIST_OK:
            try:
                browse_ids.add(int(r["Taxon id"]))
            except (ValueError, KeyError):
                pass

    # -- Filter and collect taxa from master ----------------------------------
    # First pass: collect all Art so we can resolve Underart parents.
    art_by_scientific = {}  # scientific_name → taxon_id
    taxa = []

    for r in master_rows:
        cat = r.get("Kategori", "").strip()
        if cat not in INCLUDED_CATEGORIES:
            continue

        try:
            taxon_id = int(r["Taxon id"])
        except (ValueError, KeyError):
            continue

        sort_order = parse_int(r.get("Global sorteringsordning", ""))
        scientific = r.get("Vetenskapligt namn", "").strip()
        swedish = r.get("Svenskt namn", "").strip()
        rl_category = r.get("RedListCategory", "").strip() or None
        rl_criteria = r.get("Rödlistningskriterium", "").strip() or None

        if cat == "Art":
            art_by_scientific[scientific] = taxon_id

        taxa.append({
            "taxon_id": taxon_id,
            "sort_order": sort_order,
            "scientific_name": scientific,
            "swedish_name": swedish,
            "category": cat,
            "red_list_category": rl_category,
            "red_list_criteria": rl_criteria,
            "is_birds_directive": 1 if taxon_id in birds_dir_ids else 0,
            "is_forestry_priority": 1 if taxon_id in forestry_ids else 0,
            "in_browse_list": 1 if taxon_id in browse_ids else 0,
            "parent_taxon_id": None,  # resolved in second pass
        })

    # Second pass: resolve parent_taxon_id for Underart
    # Parent = Art whose scientific name matches the first two words of the Underart.
    for t in taxa:
        if t["category"] == "Underart":
            parent_sci = first_two_words(t["scientific_name"])
            parent_id = art_by_scientific.get(parent_sci)
            t["parent_taxon_id"] = parent_id
            if parent_id is None:
                print(f"  [warn] No parent found for Underart: {t['scientific_name']}")

    # -- Write SQLite ---------------------------------------------------------
    print(f"Writing {OUT_DB}...")
    os.makedirs(os.path.dirname(OUT_DB), exist_ok=True)

    if os.path.exists(OUT_DB):
        os.remove(OUT_DB)

    con = sqlite3.connect(OUT_DB)
    cur = con.cursor()

    cur.executescript("""
        CREATE TABLE taxa (
            taxon_id            INTEGER PRIMARY KEY,
            sort_order          INTEGER,
            scientific_name     TEXT NOT NULL,
            swedish_name        TEXT NOT NULL,
            category            TEXT NOT NULL,
            red_list_category   TEXT,
            red_list_criteria   TEXT,
            is_birds_directive  INTEGER NOT NULL DEFAULT 0,
            is_forestry_priority INTEGER NOT NULL DEFAULT 0,
            in_browse_list      INTEGER NOT NULL DEFAULT 0,
            parent_taxon_id     INTEGER REFERENCES taxa(taxon_id)
        );

        CREATE INDEX idx_taxa_sort      ON taxa(sort_order);
        CREATE INDEX idx_taxa_category  ON taxa(category);
        CREATE INDEX idx_taxa_browse    ON taxa(in_browse_list);
        CREATE INDEX idx_taxa_parent    ON taxa(parent_taxon_id);
        CREATE INDEX idx_taxa_sci       ON taxa(scientific_name);
        CREATE INDEX idx_taxa_swe       ON taxa(swedish_name);
    """)

    cur.executemany("""
        INSERT INTO taxa (
            taxon_id, sort_order, scientific_name, swedish_name, category,
            red_list_category, red_list_criteria,
            is_birds_directive, is_forestry_priority,
            in_browse_list, parent_taxon_id
        ) VALUES (
            :taxon_id, :sort_order, :scientific_name, :swedish_name, :category,
            :red_list_category, :red_list_criteria,
            :is_birds_directive, :is_forestry_priority,
            :in_browse_list, :parent_taxon_id
        )
    """, taxa)

    con.commit()

    # -- Stats ----------------------------------------------------------------
    cur.execute("SELECT category, COUNT(*) FROM taxa GROUP BY category ORDER BY COUNT(*) DESC")
    print("\nTaxa by category:")
    for row in cur.fetchall():
        print(f"  {row[0]:<20} {row[1]}")

    cur.execute("SELECT COUNT(*) FROM taxa WHERE in_browse_list = 1")
    print(f"\nBrowse list taxa:    {cur.fetchone()[0]}")

    cur.execute("SELECT COUNT(*) FROM taxa WHERE is_birds_directive = 1")
    print(f"Birds Directive I:   {cur.fetchone()[0]}")

    cur.execute("SELECT COUNT(*) FROM taxa WHERE is_forestry_priority = 1")
    print(f"Forestry priority:   {cur.fetchone()[0]}")

    cur.execute("SELECT COUNT(*) FROM taxa WHERE parent_taxon_id IS NOT NULL")
    print(f"Underart with parent:{cur.fetchone()[0]}")

    con.close()
    print("\nDone.")


if __name__ == "__main__":
    main()
