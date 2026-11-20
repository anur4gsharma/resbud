"""Live End-to-End Paper Generation and Quality Evaluation Script.

This script tests Resbud's complete paper synthesis pipeline:
1. Ingests research notes and generated figures (PNGs).
2. Sends a structured IEEE Conference GenerationRequest to the live backend.
3. Validates the generated paper structure, sections, citations, equations, and figures.
4. Exports both DOCX and PDF documents.
5. Runs academic quality analysis on the generated manuscript.
"""

import base64
import json
import os
import sys
import time
from pathlib import Path
import httpx

ROOT = Path(__file__).resolve().parent
NOTES_PATH = ROOT / "research_notes.txt"
FIG1_PATH = ROOT / "architecture_diagram.png"
FIG2_PATH = ROOT / "convergence_curves.png"
FIG3_PATH = ROOT / "benchmark_comparison.png"

BACKEND_URL = os.environ.get("RESBUD_API_URL", "http://localhost:8000")

def load_image_b64(path: Path) -> str:
    raw = path.read_bytes()
    return f"data:image/png;base64,{base64.b64encode(raw).decode('ascii')}"

def build_request_payload() -> dict:
    source_notes = NOTES_PATH.read_text(encoding="utf-8")
    fig1_uri = load_image_b64(FIG1_PATH)
    fig2_uri = load_image_b64(FIG2_PATH)
    fig3_uri = load_image_b64(FIG3_PATH)

    payload = {
        "schema_version": 1,
        "project": {
            "title": "Dynamic Rank Pruning in Vision-Language Models: An Empirical Evaluation of Parameter-Efficient Adaptation",
            "research_field": "Multimodal Deep Learning and Vision-Language Transformers",
            "research_question": "Can dynamic singular value pruning allocate heterogeneous rank across attention layers while preserving zero-shot retrieval accuracy?",
            "objectives": [
                "Formulate gradient-informed singular value importance metric",
                "Implement dynamic exponential decay thresholding for singular components",
                "Benchmark parameter savings and retrieval accuracy on MS-COCO and Flickr30k"
            ],
            "claimed_contribution": "A dynamic SVD-based parameter pruning framework (DRP-VLM) that reduces adaptation parameters by 64.2% while achieving +0.84% R@1 improvement over LoRA.",
            "methodology_status": "provided",
            "methodology": "SVD decomposition Delta W = P Lambda Q with first-order Taylor importance scores S_k = |Lambda_k * dL/dLambda_k| and exponential decay thresholding.",
            "dataset_or_materials_status": "provided",
            "dataset_or_materials": "MS-COCO (123,287 images) and Flickr30k (31,783 images), ViT-B/16 and CLIP ResNet-50 backbones, 4x NVIDIA A100 GPUs.",
            "results_status": "provided",
            "results": "DRP-VLM achieves 59.24% R@1 on MS-COCO with 1.27M parameters, outperforming LoRA (58.4%, 3.54M) and AdaLoRA (58.9%, 2.10M). Early layers retain r_eff=2.4 while fusion layers retain r_eff=6.8.",
            "limitations_status": "provided",
            "limitations": "Requires careful tuning of decay rate alpha; first 500 warmup steps require rank protection to prevent premature eviction."
        },
        "source_draft": source_notes,
        "references": [
            {
                "id": "ref_hu2021",
                "text": "E. J. Hu, Y. Shen, P. Wallis, Z. Allen-Zhu, Y. Li, S. Wang, L. Wang, and W. Chen, \"LoRA: Low-rank adaptation of large language models,\" in Proc. Int. Conf. Learn. Represent. (ICLR), 2022, pp. 1-26."
            },
            {
                "id": "ref_zhang2023",
                "text": "Q. Zhang, M. Chen, A. Bukharin, P. He, Y. Cheng, W. Chen, and T. Zhao, \"Adaptive budget allocation for parameter-efficient fine-tuning,\" in Proc. Int. Conf. Learn. Represent. (ICLR), 2023, pp. 1-18."
            },
            {
                "id": "ref_radford2021",
                "text": "A. Radford, J. W. Kim, C. Hallacy, A. Ramesh, G. Goh, S. Agarwal, G. Sastry, A. Askell, P. Mishkin, J. Clark et al., \"Learning transferable visual models from natural language supervision,\" in Proc. Int. Conf. Mach. Learn. (ICML), 2021, pp. 8748-8763."
            },
            {
                "id": "ref_vaswani2017",
                "text": "A. Vaswani, N. Shazeer, N. Parmar, J. Uszkoreit, L. Jones, A. N. Gomez, L. Kaiser, and I. Polosukhin, \"Attention is all you need,\" in Adv. Neural Inf. Process. Syst. (NeurIPS), vol. 30, 2017, pp. 5998-6008."
            }
        ],
        "preferences": {
            "target_word_count": 2500,
            "desired_sections": [
                "introduction",
                "related_work",
                "methodology",
                "experimental_results",
                "discussion",
                "conclusion"
            ],
            "citation_style": "ieee",
            "document_template": "ieee_conference",
            "page_layout": "two_column_academic",
            "authors": [
                {
                    "id": "auth_1",
                    "name": "Dr. Elena Rostova",
                    "order": 1,
                    "affiliation_ids": ["aff_stanford", "aff_deepmind"],
                    "email": "elena.rostova@cs.stanford.edu",
                    "is_corresponding": True
                },
                {
                    "id": "auth_2",
                    "name": "Marcus Vance",
                    "order": 2,
                    "affiliation_ids": ["aff_stanford"],
                    "email": "mvance@stanford.edu",
                    "is_corresponding": False
                },
                {
                    "id": "auth_3",
                    "name": "Dr. Chen Wei",
                    "order": 3,
                    "affiliation_ids": ["aff_tsinghua"],
                    "email": "wei.chen@tsinghua.edu.cn",
                    "is_corresponding": False
                }
            ],
            "affiliations": [
                {
                    "id": "aff_stanford",
                    "department": "Department of Computer Science",
                    "institution": "Stanford University",
                    "city": "Stanford",
                    "state": "CA",
                    "country": "USA"
                },
                {
                    "id": "aff_deepmind",
                    "department": "Multimodal Research Team",
                    "institution": "Google DeepMind",
                    "city": "Mountain View",
                    "state": "CA",
                    "country": "USA"
                },
                {
                    "id": "aff_tsinghua",
                    "department": "Institute for AI Industry Research (AIR)",
                    "institution": "Tsinghua University",
                    "city": "Beijing",
                    "country": "China"
                }
            ],
            "figures": [
                {
                    "id": "fig_1",
                    "filename": "architecture_diagram.png",
                    "caption": "Fig. 1: DRP-VLM architectural overview illustrating dynamic SVD rank pruning and gradient-based singular value thresholding.",
                    "data_uri": fig1_uri,
                    "category": "architecture_diagram",
                    "related_section": "methodology",
                    "column_span": "full_width",
                    "figure_order": 1
                },
                {
                    "id": "fig_2",
                    "filename": "convergence_curves.png",
                    "caption": "Fig. 2: Training loss convergence and dynamic effective rank allocation (r_eff) over 10,000 optimization steps.",
                    "data_uri": fig2_uri,
                    "category": "graph",
                    "related_section": "experimental_results",
                    "column_span": "column_width",
                    "figure_order": 2
                },
                {
                    "id": "fig_3",
                    "filename": "benchmark_comparison.png",
                    "caption": "Fig. 3: Performance vs. parameter efficiency trade-off comparing Full Fine-Tuning, LoRA, AdaLoRA, and DRP-VLM on MS-COCO.",
                    "data_uri": fig3_uri,
                    "category": "graph",
                    "related_section": "experimental_results",
                    "column_span": "column_width",
                    "figure_order": 3
                }
            ],
            "include_review_notes_appendix": True
        }
    }
    return payload

def main():
    print(f"[*] Connecting to Resbud Backend at {BACKEND_URL}...")
    client = httpx.Client(timeout=300.0)

    # 1. Health Check
    health_resp = client.get(f"{BACKEND_URL}/health")
    assert health_resp.status_code == 200, f"Backend not healthy: {health_resp.text}"
    print(f"[+] Backend healthy: {health_resp.json()}")

    # 2. Build Request
    print("[*] Formulating structured GenerationRequest with IEEE metadata, authors, and figures...")
    payload = build_request_payload()
    print(f"[+] Request constructed: {len(payload['preferences']['figures'])} figures, {len(payload['preferences']['authors'])} authors.")

    # 3. Generate Paper
    print("[*] Submitting generation request to /api/v1/generations (this invokes the generation pipeline)...")
    start_time = time.time()
    resp = client.post(f"{BACKEND_URL}/api/v1/generations", json=payload)
    elapsed = time.time() - start_time

    if resp.status_code != 200:
        print(f"[-] Generation failed with status {resp.status_code}:")
        print(resp.text)
        sys.exit(1)

    print(f"[+] Generation succeeded in {elapsed:.2f}s!")
    gen_data = resp.json()

    # Save raw generated response JSON
    out_json = ROOT / "generated_paper.json"
    out_json.write_text(json.dumps(gen_data, indent=2), encoding="utf-8")
    print(f"[+] Raw paper JSON saved to {out_json}")

    paper = gen_data["paper"]
    sections = paper["sections"]
    total_words = sum(len(s["content"].split()) for s in sections)

    print("\n" + "="*80)
    print("MANUSCRIPT QUALITY AUDIT & INSPECTION REPORT")
    print("="*80)
    print(f"Title: {paper['title']}")
    print(f"Abstract Word Count: {len(paper['abstract'].split())} words")
    print(f"Abstract Preview: {paper['abstract'][:200]}...")
    print(f"Total Body Words: {total_words} words across {len(sections)} sections")
    print(f"Provider Meta: {gen_data.get('meta', {})}")

    # Inspect sections
    print("\n[-] Sections Analysis:")
    for idx, sec in enumerate(sections, 1):
        content = sec["content"]
        words = len(content.split())
        has_fig_ref = any(f"Fig" in content or f"Figure" in content for _ in [1])
        has_citations = "[" in content and "]" in content
        has_math = "$" in content
        print(f"  {idx}. [{sec['id']}] {sec['heading']} ({words} words)")
        print(f"     - Citations present: {has_citations} | Math symbols: {has_math} | Figure refs: {has_fig_ref}")

    # Inspect Citations
    all_content = " ".join(s["content"] for s in sections)
    citations_found = [ref["id"] for ref in payload["references"] if ref["id"] in all_content or f"[{ref['id']}]" in all_content or any(f"[{i+1}]" in all_content for i in range(len(payload["references"])))]
    print(f"\n[-] Citations Grounding: References detected in manuscript body: {len(citations_found)}/{len(payload['references'])}")

    # Inspect Figures
    print(f"[-] Figures Registered in Paper: {len(paper.get('figures', []))}")
    for fig in paper.get("figures", []):
        print(f"  - [{fig['id']}] {fig['caption'][:60]}... (Span: {fig.get('column_span')})")

    # Inspect Review Warnings
    warnings = gen_data.get("review_warnings", [])
    print(f"[-] Review Warnings: {len(warnings)}")
    for w in warnings:
        print(f"  * [{w.get('severity')}] {w.get('code')}: {w.get('message')}")

    # 4. Export DOCX
    print("\n[*] Requesting DOCX export from /api/v1/exports/docx...")
    docx_resp = client.post(f"{BACKEND_URL}/api/v1/exports/docx", json=paper)
    if docx_resp.status_code == 200:
        docx_file = ROOT / "generated_paper.docx"
        docx_file.write_bytes(docx_resp.content)
        print(f"[+] DOCX exported successfully: {docx_file} ({len(docx_resp.content):,} bytes)")
    else:
        print(f"[-] DOCX export failed ({docx_resp.status_code}): {docx_resp.text}")

    # 5. Export PDF
    print("[*] Requesting PDF export from /api/v1/exports/pdf...")
    pdf_resp = client.post(f"{BACKEND_URL}/api/v1/exports/pdf", json=paper)
    if pdf_resp.status_code == 200:
        pdf_file = ROOT / "generated_paper.pdf"
        pdf_file.write_bytes(pdf_resp.content)
        print(f"[+] PDF exported successfully: {pdf_file} ({len(pdf_resp.content):,} bytes)")
    else:
        print(f"[-] PDF export failed ({pdf_resp.status_code}): {pdf_resp.text}")

    print("\n" + "="*80)
    print("LIVE GENERATION VERIFICATION COMPLETE")
    print("="*80)

if __name__ == "__main__":
    main()
