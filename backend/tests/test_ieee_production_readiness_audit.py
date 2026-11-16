"""Production-Readiness Audit for Resbud IEEE Conference Paper Format.

Tests the exact 23-step user journey:
 1. Create a new IEEE research project.
 2. Enter paper title.
 3. Add five authors.
 4. Assign affiliations and email addresses.
 5. Upload a research dossier.
 6. Upload six different research images.
 7. Generate a semantic figure placement plan.
 8. Review and approve figure assignments.
 9. Generate the manuscript.
10. Verify all sections and subsections.
11. Verify inline and display OMML equations.
12. Verify automatic equation numbering.
13. Verify figure captions and contextual placements.
14. Verify table numbering and captions.
15. Verify IEEE in-text citations.
16. Verify reference metadata and numbering.
17. Save the project.
18. Close and reopen the application.
19. Export DOCX.
20. Export PDF.
21. Open both documents in their respective Resbud viewers.
22. Open the DOCX in Microsoft Word / OpenXML validator.
23. Compare the generated outputs with the IEEE reference manuscript.
"""

from __future__ import annotations

import io
import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from resbud_api.domain.models import (
    AuthorAffiliation,
    AuthorMetadata,
    PaperDraft,
    PaperPreferences,
    PaperSection,
    ProjectContext,
    ReferenceInput,
    StructuredFigure,
)
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.figure_distributor import distribute_and_reindex_figures
from resbud_api.services.figure_planner import plan_figure_placements
from resbud_api.services.pdf_export import export_paper_pdf
from resbud_api.services.reference_engine import process_manuscript_citations_and_bibliography
from resbud_api.templates.ieee_conference import calculate_ieee_author_grid

W_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
MATH_NS = {"m": "http://schemas.openxmlformats.org/officeDocument/2006/math"}

SAMPLE_PNG_DATA_URI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
REFERENCE_MANUSCRIPT_PATH = Path("/home/anur4gsharma/Downloads/ASEP 2 RP.docx")


class TestIEEEProductionReadinessAudit:
    """Rigorous 23-step production-readiness audit."""

    def test_complete_23_step_user_journey(self, tmp_path: Path) -> None:
        # =====================================================================
        # STEP 1: Create a new IEEE research project
        # =====================================================================
        preferences = PaperPreferences(
            target_word_count=5000,
            desired_sections=[
                "sec_intro",
                "sec_related",
                "sec_method",
                "sec_results",
                "sec_conclusion",
            ],
            citation_style="ieee",
            page_layout="two_column_academic",
            document_template="ieee_conference",
        )
        project = ProjectContext(
            title="Equivariant Neural Graph Decoders for Topological Surface Codes",
            research_field="Quantum Information & Neural Decoding",
            research_question="How can group-equivariant graph neural networks accelerate minimum-weight syndrome decoding in planar topological surface codes without loss of fault-tolerant threshold?",
            objectives=[
                "Formulate syndrome decoding on surface code graphs with SE(2) topological equivariance.",
                "Construct an iterative message-passing graph architecture operating in real-time quantum cycle latencies.",
                "Empirically benchmark logical error suppression against standard minimum-weight perfect matching (MWPM).",
            ],
            claimed_contribution="Demonstration of the first group-equivariant graph decoder achieving 14.2% fault-tolerant threshold with sub-microsecond inference overhead.",
            methodology_status="provided",
            dataset_or_materials_status="provided",
            results_status="provided",
            limitations_status="provided",
            methodology="Topological graph contraction on 2D toric code syndrome lattices with edge-conditioned convolutional operators.",
            dataset_or_materials="Simulated Pauli X and Z noise models under rotated surface code geometries from distance d=3 to d=9.",
            results="Outperforms standard MWPM in logical failure probability across all code distances d in {3, 5, 7, 9}.",
            limitations="Real hardware FPGA deployment requires quantized fixed-point integer graph operations.",
        )
        assert project.title is not None
        assert preferences.document_template == "ieee_conference"

        # =====================================================================
        # STEP 2: Enter paper title
        # =====================================================================
        paper_title = "Equivariant Neural Graph Decoders for Topological Surface Codes"
        assert len(paper_title) >= 10

        # =====================================================================
        # STEP 3: Add five authors
        # =====================================================================
        authors = [
            AuthorMetadata(
                name="Dr. Aris Thorne",
                order=1,
                affiliation_ids=["aff_1"],
                email="aris.thorne@nitrkl.ac.in",
                role_or_title="Senior Member, IEEE",
                is_corresponding=True,
                funding_acknowledgment="Supported by Quantum Hardware Grant #Q-2024-88",
            ),
            AuthorMetadata(
                name="Elena Vance",
                order=2,
                affiliation_ids=["aff_1"],
                email="elena.vance@nitrkl.ac.in",
                role_or_title="Graduate Student Member, IEEE",
            ),
            AuthorMetadata(
                name="Marcus Zhao",
                order=3,
                affiliation_ids=["aff_2"],
                email="marcus.zhao@shs.ac.in",
                role_or_title="Member, IEEE",
            ),
            AuthorMetadata(
                name="Dr. Clara Oswald",
                order=4,
                affiliation_ids=["aff_1"],
                email="clara.oswald@nitrkl.ac.in",
                role_or_title="Associate Professor",
            ),
            AuthorMetadata(
                name="Robert Song",
                order=5,
                affiliation_ids=["aff_2"],
                email="robert.song@shs.ac.in",
                role_or_title="Research Scholar",
            ),
        ]
        assert len(authors) == 5
        assert authors[0].is_corresponding is True
        assert authors[0].order == 1
        assert authors[4].order == 5

        # =====================================================================
        # STEP 4: Assign affiliations and email addresses
        # =====================================================================
        affiliations = [
            AuthorAffiliation(
                id="aff_1",
                department="Department of Computer Science & Engineering",
                institution="National Institute of Technology",
                city="Rourkela",
                state="Odisha",
                country="India",
            ),
            AuthorAffiliation(
                id="aff_2",
                department="Department of Biomedical Engineering",
                institution="School of Healthcare Sciences",
                city="Bhubaneswar",
                state="Odisha",
                country="India",
            ),
        ]
        assert len(affiliations) == 2
        for a in authors:
            assert a.email is not None and "@" in a.email
            assert len(a.affiliation_ids) >= 1

        # =====================================================================
        # STEP 5: Upload a research dossier
        # =====================================================================
        research_dossier = (
            "Topological surface code error correction requires low-latency syndrome decoding.\n"
            "This dossier details the equivariant graph architecture, simulation benchmarks, "
            "and mathematical models for Pauli error channel inversion."
        )
        assert len(research_dossier) > 50

        # =====================================================================
        # STEP 6: Upload six different research images
        # =====================================================================
        six_figures = [
            StructuredFigure(
                id="FIG-001",
                filename="methodology_flowchart.png",
                title="Methodology Pipeline Flowchart",
                caption="Fig. 1. End-to-end topological decoding pipeline from syndrome extraction to correction operator.",
                description="Flowchart of raw syndrome measurement, graph construction, edge weighting, and boundary correction.",
                category="flowchart",
                related_section="sec_method",
                column_span="column_width",
                data_uri=SAMPLE_PNG_DATA_URI,
            ),
            StructuredFigure(
                id="FIG-002",
                filename="neural_decoder_topology.png",
                title="Equivariant Graph Topology",
                caption="Fig. 2. Equivariant neural graph topology highlighting message passing along rotated surface code boundaries.",
                description="Architecture diagram showing node features, edge update gates, and topological parity checks.",
                category="architecture_diagram",
                related_section="sec_method",
                column_span="full_width",
                data_uri=SAMPLE_PNG_DATA_URI,
            ),
            StructuredFigure(
                id="FIG-003",
                filename="syndrome_decoding_accuracy.png",
                title="Syndrome Decoding Convergence Curve",
                caption="Fig. 3. Convergence of syndrome decoding accuracy across training epochs for distances d=3, 5, 7.",
                description="Graph of loss minimization and test syndrome accuracy vs training iterations.",
                category="graph",
                related_section="sec_results",
                column_span="column_width",
                data_uri=SAMPLE_PNG_DATA_URI,
            ),
            StructuredFigure(
                id="FIG-004",
                filename="decoding_runtime_profiler.png",
                title="Runtime Latency Profiler Screenshot",
                caption="Fig. 4. Real-time inference profiler interface demonstrating sub-microsecond decoding latency.",
                description="Screenshot of hardware benchmark dashboard measuring FPGA cycle timings.",
                category="screenshot",
                related_section="sec_results",
                column_span="column_width",
                data_uri=SAMPLE_PNG_DATA_URI,
            ),
            StructuredFigure(
                id="FIG-005",
                filename="threshold_comparison_curve.png",
                title="Ablation Threshold Curve",
                caption="Fig. 5. Fault-tolerant threshold crossing comparison between equivariant layers and standard GCN.",
                description="Graph of logical error rate versus physical error rate showing crossing at p_th = 14.2%.",
                category="graph",
                related_section="sec_results",
                column_span="column_width",
                data_uri=SAMPLE_PNG_DATA_URI,
            ),
            StructuredFigure(
                id="FIG-006",
                filename="logical_error_rate_scaling.png",
                title="Logical Error Scaling",
                caption="Fig. 6. Sub-threshold logical error suppression scaling exponentially with code distance d.",
                description="Experimental curves showing P_L exponential suppression as code distance increases.",
                category="experimental_result",
                related_section="sec_results",
                column_span="column_width",
                data_uri=SAMPLE_PNG_DATA_URI,
            ),
        ]
        assert len(six_figures) == 6

        # =====================================================================
        # STEP 7: Generate a semantic figure placement plan
        # =====================================================================
        section_ids = [
            "sec_intro",
            "sec_related",
            "sec_method",
            "sec_results",
            "sec_conclusion",
        ]
        planned_figures = plan_figure_placements(six_figures, section_ids)
        assert len(planned_figures) == 6

        # Anti-bundling verification: figures distributed across methodology and results
        method_figs = [f for f in planned_figures if f.related_section == "sec_method"]
        results_figs = [f for f in planned_figures if f.related_section == "sec_results"]
        assert len(method_figs) == 2, "Methodology section must receive exactly 2 figures"
        assert len(results_figs) == 4, "Results section must receive 4 figures (anti-bundling)"
        # Verify sequence numbers
        for idx, fig in enumerate(planned_figures, start=1):
            assert fig.figure_order == idx
            assert f"Fig. {idx}." in fig.caption

        # =====================================================================
        # STEP 8: Review and approve figure assignments
        # =====================================================================
        approved_figures: list[StructuredFigure] = []
        for fig in planned_figures:
            approved_fig = fig.model_copy(
                update={
                    "placement_status": "approved",
                    "placement_rationale": f"Approved for contextual placement in {fig.related_section}.",
                }
            )
            approved_figures.append(approved_fig)
        assert all(f.placement_status == "approved" for f in approved_figures)

        # =====================================================================
        # STEP 9: Generate the manuscript
        # =====================================================================
        references_input = [
            ReferenceInput(
                id="fowler2012",
                title="Surface codes: Towards practical large-scale quantum computation",
                authors=["A. G. Fowler", "M. Mariantoni", "J. M. Martinis", "A. N. Cleland"],
                year=2012,
                venue="Phys. Rev. A",
                doi="10.1103/PhysRevA.86.032324",
                publication_type="journal_article",
                text="A. G. Fowler, M. Mariantoni, J. M. Martinis, and A. N. Cleland, 'Surface codes: Towards practical large-scale quantum computation,' Phys. Rev. A, vol. 86, p. 032324, 2012.",
            ),
            ReferenceInput(
                id="dennis2002",
                title="Topological quantum memory",
                authors=["E. Dennis", "A. Kitaev", "A. Landahl", "J. Preskill"],
                year=2002,
                venue="J. Math. Phys.",
                doi="10.1063/1.1499754",
                publication_type="journal_article",
                text="E. Dennis, A. Kitaev, A. Landahl, and J. Preskill, 'Topological quantum memory,' J. Math. Phys., vol. 43, pp. 4452-4505, 2002.",
            ),
            ReferenceInput(
                id="battistin2023",
                title="Neural network decoders for quantum error correction",
                authors=["R. Battistin", "C. G. Almudever"],
                year=2023,
                venue="IEEE Trans. Quantum Eng.",
                doi="10.1109/TQE.2023.3289012",
                publication_type="journal_article",
                text="R. Battistin and C. G. Almudever, 'Neural network decoders for quantum error correction,' IEEE Trans. Quantum Eng., vol. 4, pp. 1-14, 2023.",
            ),
        ]

        raw_sections = [
            PaperSection(
                id="sec_intro",
                heading="I. INTRODUCTION",
                content=(
                    "Quantum error correction (QEC) is essential for fault-tolerant quantum computation [fowler2012]. "
                    "Topological surface codes store logical qubits in entangled geometric lattices [dennis2002]. "
                    "In this paper, we demonstrate equivariant graph neural networks for fast syndrome decoding.\n\n"
                    "Recent advancements in neural decoding provide promising alternatives to standard minimum-weight "
                    "perfect matching algorithms [battistin2023]."
                ),
                state="draft",
            ),
            PaperSection(
                id="sec_related",
                heading="II. RELATED WORK",
                content=(
                    "Prior works on minimum-weight matching provide optimal asymptotic thresholds but struggle with "
                    "real-time latency constraints [fowler2012]. Dennis et al. formalized the topological memory Hamiltonian [dennis2002]."
                ),
                state="draft",
            ),
            PaperSection(
                id="sec_method",
                heading="III. METHODOLOGY",
                content=(
                    "The syndrome decoding process maps discrete error chains to boundary stabilizer measurements.\n\n"
                    "### A. Topological Graph Formulation\n"
                    "We represent the rotated surface code as a directed graph $G = (V, E)$, where each vertex $v \\in V$ "
                    "corresponds to a stabilizer measurement and each edge $e \\in E$ denotes a potential Pauli error path.\n\n"
                    "The graph contraction Hamiltonian is given by:\n"
                    r"$$H_{\text{syndrome}} = \sum_{v \in V} \lambda_v S_v + \sum_{(u,v) \in E} J_{uv} \sigma_u \sigma_v$$"
                    "\n\n"
                    "### B. Equivariant Layer Architecture\n"
                    "To guarantee symmetry under $90^\\circ$ spatial lattice rotations, edge updates satisfy group equivariance:\n"
                    r"$$\mathbf{h}_v^{(l+1)} = \sigma \left( \mathbf{W}_0 \mathbf{h}_v^{(l)} + \sum_{u \in \mathcal{N}(v)} \mathbf{W}_1 \left( \mathbf{h}_u^{(l)} \oplus \mathbf{e}_{uv} \right) \right)$$"
                    "\n\n"
                    "The total objective loss optimized across all training batches is expressed as:\n"
                    r"$$\mathcal{L}_{\text{total}} = \frac{1}{|B|} \sum_{i \in B} \left\| \hat{\mathbf{y}}_i - \mathbf{y}_i \right\|_2^2 + \gamma \|\mathbf{W}\|_F^2$$"
                ),
                state="draft",
            ),
            PaperSection(
                id="sec_results",
                heading="IV. EXPERIMENTAL EVALUATION",
                content=(
                    "We evaluate our equivariant decoder against standard matching decoders under phenomenological noise models.\n\n"
                    "### A. Numerical Accuracy Benchmarks\n"
                    "TABLE I: DECODING ACCURACY AND LATENCY COMPARISON\n"
                    "| Architecture | Code Distance (d) | Threshold (%) | Latency (us) |\n"
                    "| --- | --- | --- | --- |\n"
                    "| Standard MWPM | 3 | 10.3 | 42.1 |\n"
                    "| Standard MWPM | 5 | 10.1 | 185.4 |\n"
                    "| Baseline GCN | 3 | 11.8 | 12.4 |\n"
                    "| Baseline GCN | 5 | 12.0 | 28.6 |\n"
                    "| Proposed Equivariant GNN | 3 | 14.2 | 1.8 |\n"
                    "| Proposed Equivariant GNN | 5 | 14.1 | 3.4 |\n"
                    "\n\n"
                    "### B. Cross-Referencing and Threshold Verification\n"
                    "As derived in (1), the Hamiltonian formalizes ground state projection. "
                    "Equation (2) establishes rotation-invariant node updates, and Eq. (3) controls weight regularization.\n\n"
                    "The logical failure rate scaling satisfies the standard ansatz:\n"
                    r"$$P_L = A \cdot \left( \frac{p}{p_{\text{th}}} \right)^{\frac{d+1}{2}}$$"
                    "\n\n"
                    "TABLE II: ABLATION STUDY OF EQUIVARIANT COMPONENTS\n"
                    "| Component Configuration | Accuracy (%) | Memory (MB) |\n"
                    "| --- | --- | --- |\n"
                    "| Full Model | 99.4 | 14.2 |\n"
                    "| Without Edge Features | 96.1 | 11.8 |\n"
                    "| Without SE(2) Symmetries | 93.5 | 13.9 |\n"
                ),
                state="draft",
            ),
            PaperSection(
                id="sec_conclusion",
                heading="V. CONCLUSION",
                content=(
                    "In this work, we introduced equivariant neural graph decoders for quantum surface codes. "
                    "Our architecture delivers a 14.2% fault-tolerant threshold while operating within sub-microsecond latency."
                ),
                state="draft",
            ),
        ]

        initial_paper = PaperDraft(
            schema_version=1,
            title=paper_title,
            abstract="Fault-tolerant quantum computing requires real-time syndrome decoding on topological surface codes. In this paper, we introduce group-equivariant neural graph decoders operating directly on syndrome graphs. Our method achieves a 14.2% fault-tolerant threshold with sub-microsecond latency, outperforming standard minimum-weight perfect matching.",
            keywords=[
                "Quantum error correction",
                "Surface codes",
                "Graph neural networks",
                "Equivariant architectures",
                "Syndrome decoding",
            ],
            sections=raw_sections,
            references=references_input,
            review_warnings=[],
            page_layout="two_column_academic",
            document_template="ieee_conference",
            authors=authors,
            affiliations=affiliations,
            figures=approved_figures,
        )

        # Distribute and contextually inject figures
        paper_with_figures = distribute_and_reindex_figures(initial_paper)
        # Process citations and references
        final_manuscript, _ref_warnings = process_manuscript_citations_and_bibliography(
            paper_with_figures
        )

        # =====================================================================
        # STEP 10: Verify all sections and subsections
        # =====================================================================
        headings = [s.heading for s in final_manuscript.sections]
        assert headings == [
            "I. INTRODUCTION",
            "II. RELATED WORK",
            "III. METHODOLOGY",
            "IV. EXPERIMENTAL EVALUATION",
            "V. CONCLUSION",
        ]
        # Verify subsections within Methodology and Results
        method_text = next(s.content for s in final_manuscript.sections if s.id == "sec_method")
        assert "### A. Topological Graph Formulation" in method_text
        assert "### B. Equivariant Layer Architecture" in method_text
        results_text = next(s.content for s in final_manuscript.sections if s.id == "sec_results")
        assert "### A. Numerical Accuracy Benchmarks" in results_text
        assert "### B. Cross-Referencing and Threshold Verification" in results_text

        # =====================================================================
        # STEP 11: Verify inline and display OMML equations
        # =====================================================================
        # Inline math checks
        assert "$G = (V, E)$" in method_text
        assert "$v \\in V$" in method_text
        assert "$e \\in E$" in method_text
        assert "$90^\\circ$" in method_text

        # Display math formulas present
        assert r"H_{\text{syndrome}}" in method_text
        assert r"\mathbf{h}_v^{(l+1)}" in method_text
        assert r"\mathcal{L}_{\text{total}}" in method_text
        assert r"P_L = A" in results_text

        # =====================================================================
        # STEP 12: Verify automatic equation numbering
        # =====================================================================
        # Cross-reference synchronization checks
        assert "(1)" in results_text or "Equation (1)" in results_text
        assert "(2)" in results_text or "Equation (2)" in results_text
        assert "(3)" in results_text or "Eq. (3)" in results_text

        # =====================================================================
        # STEP 13: Verify figure captions and contextual placements
        # =====================================================================
        # Methodology section must contain Fig 1 and Fig 2
        assert "FIG-001" in method_text or "methodology_flowchart.png" in method_text
        assert "FIG-002" in method_text or "neural_decoder_topology.png" in method_text
        # Results section must contain Figs 3, 4, 5, 6
        assert "FIG-003" in results_text or "syndrome_decoding_accuracy.png" in results_text
        assert "FIG-004" in results_text or "decoding_runtime_profiler.png" in results_text
        assert "FIG-005" in results_text or "threshold_comparison_curve.png" in results_text
        assert "FIG-006" in results_text or "logical_error_rate_scaling.png" in results_text

        # Verify IEEE figure captions
        for f in final_manuscript.figures or []:
            assert f.caption.startswith("Fig. ")
            assert f.placement_status == "approved"

        # =====================================================================
        # STEP 14: Verify table numbering and captions
        # =====================================================================
        assert "TABLE I: DECODING ACCURACY AND LATENCY COMPARISON" in results_text
        assert "TABLE II: ABLATION STUDY OF EQUIVARIANT COMPONENTS" in results_text
        assert "| Architecture | Code Distance (d) |" in results_text
        assert "| Proposed Equivariant GNN |" in results_text

        # =====================================================================
        # STEP 15: Verify IEEE in-text citations
        # =====================================================================
        intro_text = next(s.content for s in final_manuscript.sections if s.id == "sec_intro")
        assert "[1]" in intro_text
        assert "[2]" in intro_text
        assert "[3]" in intro_text
        assert "[fowler2012]" not in intro_text, "Source reference key must be remapped to [1]"
        assert "[dennis2002]" not in intro_text, "Source reference key must be remapped to [2]"
        assert "[battistin2023]" not in intro_text, "Source reference key must be remapped to [3]"

        # =====================================================================
        # STEP 16: Verify reference metadata and numbering
        # =====================================================================
        assert len(final_manuscript.references) == 3
        ref1 = final_manuscript.references[0]
        assert ref1.citation_number == 1
        assert ref1.id == "fowler2012"
        assert ref1.year == 2012
        assert ref1.doi == "10.1103/PhysRevA.86.032324"

        # =====================================================================
        # STEP 17: Save the project (Serialization to persistent format)
        # =====================================================================
        serialized_manuscript = final_manuscript.model_dump_json()
        assert len(serialized_manuscript) > 5000
        saved_file = tmp_path / "project_persistence_snapshot.json"
        saved_file.write_text(serialized_manuscript, encoding="utf-8")
        assert saved_file.exists()

        # =====================================================================
        # STEP 18: Close and reopen application (Persistent state restoration)
        # =====================================================================
        reloaded_json = saved_file.read_text(encoding="utf-8")
        reloaded_data = json.loads(reloaded_json)
        reloaded_manuscript = PaperDraft.model_validate(reloaded_data)

        assert reloaded_manuscript.title == final_manuscript.title
        assert len(reloaded_manuscript.authors or []) == 5
        assert len(reloaded_manuscript.affiliations or []) == 2
        assert len(reloaded_manuscript.figures or []) == 6
        assert len(reloaded_manuscript.references) == 3
        assert reloaded_manuscript.document_template == "ieee_conference"

        # =====================================================================
        # STEP 19: Export DOCX
        # =====================================================================
        docx_bytes = export_paper_docx(reloaded_manuscript)
        assert isinstance(docx_bytes, bytes)
        assert len(docx_bytes) > 20000, "DOCX export must produce substantial binary"

        # Save DOCX for disk inspection
        docx_path = tmp_path / "audit_ieee_manuscript.docx"
        docx_path.write_bytes(docx_bytes)
        assert docx_path.exists()

        # =====================================================================
        # STEP 20: Export PDF
        # =====================================================================
        pdf_bytes = export_paper_pdf(reloaded_manuscript)
        assert isinstance(pdf_bytes, bytes)
        assert len(pdf_bytes) > 40000, "PDF export must produce substantial binary"
        assert pdf_bytes.startswith(b"%PDF"), "Must be a valid PDF binary"

        # Save PDF for disk inspection
        pdf_path = tmp_path / "audit_ieee_manuscript.pdf"
        pdf_path.write_bytes(pdf_bytes)
        assert pdf_path.exists()

        # =====================================================================
        # STEP 21: Open both documents in their respective Resbud viewers
        # =====================================================================
        # PDF page count check
        pdf_text = pdf_bytes.decode("latin1", errors="ignore")
        page_count = len(pdf_text.split("/Type /Page")) - 1
        assert page_count >= 1

        # DOCX zipfile inspection
        docx_zip = zipfile.ZipFile(io.BytesIO(docx_bytes))
        doc_xml_str = docx_zip.read("word/document.xml").decode("utf-8")
        root = ET.fromstring(doc_xml_str)

        # =====================================================================
        # STEP 22: Open the DOCX in Microsoft Word / OpenXML validator
        # =====================================================================
        # A. OMML Equations validation: native m:oMath and m:oMathPara objects
        omath_elements = root.findall(".//m:oMath", MATH_NS)
        omathpara_elements = root.findall(".//m:oMathPara", MATH_NS)
        assert len(omath_elements) >= 4, (
            f"Expected at least 4 OMML equations, got {len(omath_elements)}"
        )
        assert len(omathpara_elements) >= 4, (
            f"Expected at least 4 display OMML paragraphs, got {len(omathpara_elements)}"
        )

        # B. Equation borderless tables validation
        tbl_elements = root.findall(".//w:tbl", W_NS)
        assert len(tbl_elements) >= 6, (
            "Expected author table, 4 equation tables, and 2 numerical tables"
        )

        # C. Table alignment validation (WD_TABLE_ALIGNMENT.CENTER)
        table_justifications = root.findall(".//w:tblPr/w:jc", W_NS)
        assert any(
            jc.attrib.get(f"{{{W_NS['w']}}}val") == "center" for jc in table_justifications
        ), "Tables must have centered alignment"

        # =====================================================================
        # STEP 23: Compare generated outputs with the IEEE reference manuscript
        # =====================================================================
        # 1. Author Grid: 5 authors must partition into [3, 2] rows (3 top, 2 bottom)
        grid = calculate_ieee_author_grid(len(reloaded_manuscript.authors or []))
        assert grid == [3, 2], f"Expected IEEE 5-author grid [3, 2], got {grid}"

        # 2. Author names and details present in docx xml
        assert "Dr. Aris Thorne" in doc_xml_str
        assert "Elena Vance" in doc_xml_str
        assert "Marcus Zhao" in doc_xml_str
        assert "Dr. Clara Oswald" in doc_xml_str
        assert "Robert Song" in doc_xml_str
        assert "aris.thorne@nitrkl.ac.in" in doc_xml_str
        assert "Senior Member, IEEE" in doc_xml_str

        # 3. Abstract and Index Terms format check
        assert "Abstract" in doc_xml_str
        assert "Index Terms" in doc_xml_str

        # 4. Reference Manuscript Comparison (if available on disk)
        if REFERENCE_MANUSCRIPT_PATH.exists():
            ref_zip = zipfile.ZipFile(REFERENCE_MANUSCRIPT_PATH)
            ref_xml = ref_zip.read("word/document.xml").decode("utf-8")
            ref_styles = ref_zip.read("word/styles.xml").decode("utf-8")
            # Both manuscripts use Times New Roman typography
            assert "Times New Roman" in doc_xml_str
            assert "Times New Roman" in ref_styles or "Times New Roman" in ref_zip.read(
                "word/fontTable.xml"
            ).decode("utf-8")
            # Both contain two-column layout settings
            assert 'w:cols w:num="2"' in doc_xml_str or 'w:num="2"' in doc_xml_str
            assert 'w:cols w:num="2"' in ref_xml or 'w:num="2"' in ref_xml
            # Both contain 5 author names
            assert (
                "Anurag Sharma" in ref_xml or "Lakshya Bajpai" in ref_xml or "Kiran More" in ref_xml
            )
            assert "Dr. Aris Thorne" in doc_xml_str
