import pathlib
import sys

import docx
from docx.shared import RGBColor
from starlette.testclient import TestClient

from resbud_api.core.settings import Settings
from resbud_api.main import create_app
from resbud_api.providers.fake import FakeProvider

MD_PATH = pathlib.Path("/home/anur4gsharma/college/CP/FODS/quantum_notes.md")
DOCX_OUT_PATH = pathlib.Path("/home/anur4gsharma/college/CP/FODS/quantum_paper.docx")
DOCX_DOWNLOADS_PATH = pathlib.Path("/home/anur4gsharma/Downloads/quantum_paper.docx")


def test_markdown_to_docx_pipeline() -> None:
    content = MD_PATH.read_text(encoding="utf-8")
    assert content, "Markdown content cannot be empty"

    payload = {
        "schema_version": 1,
        "project": {
            "title": "Scalable Quantum Error Correction via Equivariant Neural Graph Decoders",
            "research_field": "Quantum Information & Computing",
            "research_question": "How do equivariant message-passing neural networks scale?",
            "objectives": [
                "Benchmark logical error rates across distance 3, 5, and 7.",
                "Evaluate inference runtime and memory latency on GPU accelerators.",
                "Formulate an equivariant message-passing architecture.",
            ],
            "claimed_contribution": "We demonstrate a 23% reduction in logical error rates.",
            "methodology_status": "provided",
            "methodology": "We simulate planar surface codes using Stim under depolarizing noise.",
            "dataset_or_materials_status": "not_available",
            "results_status": "provided",
            "results": "At distance 5, logical error drops by 23% and latency to 0.81ms.",
            "limitations_status": "provided",
            "limitations": "Restricted to Markovian Pauli error channels.",
        },
        "source_draft": content,
        "references": [
            {
                "id": "fowler2012",
                "text": "Fowler, A. G., et al. (2012). Surface codes. Phys. Rev. A, 86, 032324.",
            },
            {
                "id": "dennis2002",
                "text": "Dennis, E., et al. (2002). Topological quantum memory. JMP, 43, 4452.",
            },
        ],
        "preferences": {
            "citation_style": "ieee",
            "desired_sections": [
                "introduction",
                "methodology",
                "results",
                "discussion",
                "conclusion",
            ],
            "target_word_count": 2500,
        },
    }

    app = create_app(
        Settings(environment="test", generation_provider="fake", _env_file=None),
        generation_provider=FakeProvider(),
    )
    with TestClient(app) as client:
        gen_resp = client.post("/api/v1/generations", json=payload)
        assert gen_resp.status_code == 200, f"Generation failed: {gen_resp.text}"

        gen_data = gen_resp.json()
        paper = gen_data["paper"]
        assert paper["title"], "Paper must have a title"
        assert len(paper["sections"]) >= 3, "Paper must have sections"

        export_resp = client.post("/api/v1/exports/docx", json=paper)
        assert export_resp.status_code == 200, f"Export failed: {export_resp.text}"
        docx_bytes = export_resp.content
        assert len(docx_bytes) > 5000, "DOCX file must be non-empty"

        DOCX_OUT_PATH.write_bytes(docx_bytes)
        DOCX_DOWNLOADS_PATH.write_bytes(docx_bytes)

        doc = docx.Document(str(DOCX_OUT_PATH))
        found_title = False
        found_abstract = False
        black_heading_runs = 0

        for p in doc.paragraphs:
            text = p.text.strip()
            if not text:
                continue
            if text == paper["title"]:
                found_title = True
            if "Abstract" in text:
                found_abstract = True

            if p.style.name.startswith("Heading"):
                for run in p.runs:
                    if run.font.color and run.font.color.rgb:
                        assert run.font.color.rgb == RGBColor(0, 0, 0)
                        black_heading_runs += 1
                    if run.font.name:
                        assert run.font.name == "Times New Roman"

        assert found_title
        assert found_abstract
        assert black_heading_runs > 0


if __name__ == "__main__":
    test_markdown_to_docx_pipeline()
    print("ALL CHECKS PASSED!")
    sys.exit(0)
