import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

os.makedirs('test_assets', exist_ok=True)

# 1. Create Research Notes (.txt)
research_notes = """# Research Project: Dynamic Rank Pruning in Vision-Language Models (DRP-VLM)

## Abstract
Parameter-efficient fine-tuning (PEFT) has become critical for adapting large vision-language foundation models to specialized multimodal downstream tasks. While Low-Rank Adaptation (LoRA) applies uniform intrinsic rank across all weight matrices, attention layers exhibit heterogeneous parameter sensitivity. In this work, we propose Dynamic Rank Pruning for Vision-Language Models (DRP-VLM), a gradient-informed rank pruning framework that dynamically allocates singular values during gradient descent. Across MS-COCO and Flickr30k benchmarks, DRP-VLM reduces active adaptation parameters by 64.2% relative to standard LoRA while improving cross-modal Retrieval Recall@1 by +0.84%.

## Research Field
Multimodal Deep Learning, Vision-Language Transformers, Parameter-Efficient Adaptation.

## Research Questions & Hypotheses
1. Can dynamic singular value thresholding outperform fixed rank allocation across heterogeneous cross-attention layers?
2. Does layer-wise singular value importance correlate directly with cross-modal token alignment entropy?

## Methodology & Formulation
For a pre-trained frozen weight matrix W0 in R^{d1 x d2}, standard adaptation models the weight update as:
W = W0 + Delta W = W0 + P * Lambda * Q
where P in R^{d1 x r}, Lambda in R^{r x r} (diagonal singular values), and Q in R^{r x d2}.

The dynamic importance score S_k for each k-th singular value is computed via first-order Taylor approximation of the loss L:
S_k = | Lambda_{k,k} * (d L / d Lambda_{k,k}) |

During training epoch t, singular components with importance scores below dynamic threshold tau_t = alpha * exp(-t / T) are zeroed out and pruned from the backpropagation computation graph:
Lambda_pruned = diag( { Lambda_{k,k} if S_k >= tau_t else 0 } )

## Experimental Setup & Datasets
- Foundation Backbones: ViT-B/16 and CLIP ResNet-50.
- Datasets: MS-COCO (123,287 images, 5 captions/image) and Flickr30k (31,783 images).
- Optimization: AdamW, initial lr = 2e-4, cosine annealing schedule over 15 epochs.
- Hardware: 4x NVIDIA A100-SXM4 (80GB).

## Key Empirical Findings
- Baseline LoRA (r=8, alpha=16): 3.54M trainable parameters, MS-COCO R@1 = 58.4%.
- AdaLoRA (Zhang et al.): 2.10M trainable parameters, MS-COCO R@1 = 58.9%.
- DRP-VLM (Proposed): 1.27M trainable parameters, MS-COCO R@1 = 59.24%.
- Cross-attention layers in early transformer blocks retain lower effective rank (r_eff = 2.4) compared to late-stage multimodal fusion layers (r_eff = 6.8).

## Limitations
- Pruning schedule requires careful calibration of the exponential decay parameter alpha.
- High gradient variance during the first 500 warmup steps can cause premature rank eviction if unmitigated.

## Authoritative References
[1] E. J. Hu, Y. Shen, P. Wallis, Z. Allen-Zhu, Y. Li, S. Wang, L. Wang, and W. Chen, "LoRA: Low-rank adaptation of large language models," in Proc. Int. Conf. Learn. Represent. (ICLR), 2022, pp. 1-26.
[2] Q. Zhang, M. Chen, A. Bukharin, P. He, Y. Cheng, W. Chen, and T. Zhao, "Adaptive budget allocation for parameter-efficient fine-tuning," in Proc. Int. Conf. Learn. Represent. (ICLR), 2023, pp. 1-18.
[3] A. Radford, J. W. Kim, C. Hallacy, A. Ramesh, G. Goh, S. Agarwal, G. Sastry, A. Askell, P. Mishkin, J. Clark et al., "Learning transferable visual models from natural language supervision," in Proc. Int. Conf. Mach. Learn. (ICML), 2021, pp. 8748-8763.
[4] A. Vaswani, N. Shazeer, N. Parmar, J. Uszkoreit, L. Jones, A. N. Gomez, L. Kaiser, and I. Polosukhin, "Attention is all you need," in Adv. Neural Inf. Process. Syst. (NeurIPS), vol. 30, 2017, pp. 5998-6008.
"""

with open('test_assets/research_notes.txt', 'w') as f:
    f.write(research_notes.strip())

# 2. Figure 1: Model Architecture Flowchart
plt.figure(figsize=(7, 3.5), dpi=200)
plt.style.use('seaborn-v0_8-whitegrid' if 'seaborn-v0_8-whitegrid' in plt.style.available else 'default')
fig, ax = plt.subplots(figsize=(7, 3.2), dpi=200)
ax.axis('off')

# Diagram boxes
boxes = [
    ("Input Tokens\n(Image & Text)", (0.1, 0.5), "#E0F2FE", "#0284C7"),
    ("Frozen Backbone\nW0 in R^{d1 x d2}", (0.35, 0.7), "#F1F5F9", "#64748B"),
    ("Dynamic SVD\nP * Lambda * Q", (0.35, 0.3), "#CCFBF1", "#0D9488"),
    ("Gradient Sorter\nS_k = |Lambda * dL/dLambda|", (0.65, 0.3), "#FEF3C7", "#D97706"),
    ("Active Rank\nSelection", (0.88, 0.3), "#DCFCE7", "#16A34A"),
    ("Combined Output\nW0*x + Delta W*x", (0.88, 0.7), "#F3E8FF", "#9333EA")
]

for name, (x, y), facecolor, edgecolor in boxes:
    ax.text(x, y, name, ha='center', va='center', fontsize=8, fontweight='bold',
            bbox=dict(boxstyle="round,pad=0.5", facecolor=facecolor, edgecolor=edgecolor, lw=1.5))

# Draw arrows
ax.annotate('', xy=(0.25, 0.7), xytext=(0.18, 0.55), arrowprops=dict(arrowstyle="->", lw=1.5, color="#475569"))
ax.annotate('', xy=(0.25, 0.3), xytext=(0.18, 0.45), arrowprops=dict(arrowstyle="->", lw=1.5, color="#0D9488"))
ax.annotate('', xy=(0.53, 0.3), xytext=(0.46, 0.3), arrowprops=dict(arrowstyle="->", lw=1.5, color="#0D9488"))
ax.annotate('', xy=(0.78, 0.3), xytext=(0.75, 0.3), arrowprops=dict(arrowstyle="->", lw=1.5, color="#D97706"))
ax.annotate('', xy=(0.88, 0.58), xytext=(0.88, 0.42), arrowprops=dict(arrowstyle="->", lw=1.5, color="#16A34A"))
ax.annotate('', xy=(0.78, 0.7), xytext=(0.46, 0.7), arrowprops=dict(arrowstyle="->", lw=1.5, color="#475569"))

plt.title("Fig. 1: DRP-VLM Architecture with Dynamic Singular Value Pruning", fontsize=10, fontweight='bold', pad=12)
plt.tight_layout()
plt.savefig('test_assets/architecture_diagram.png', bbox_inches='tight')
plt.close()

# 3. Figure 2: Convergence Curves
fig, ax1 = plt.subplots(figsize=(6, 3.2), dpi=200)
steps = np.linspace(0, 10000, 100)
loss_lora = 2.4 * np.exp(-steps / 3500) + 0.45 + np.random.normal(0, 0.015, 100)
loss_drp = 2.4 * np.exp(-steps / 3200) + 0.38 + np.random.normal(0, 0.015, 100)
rank_active = 8 - 5.5 / (1 + np.exp(-(steps - 2500) / 1200))

color = '#0284C7'
ax1.set_xlabel('Optimization Steps', fontsize=9)
ax1.set_ylabel('Training Cross-Entropy Loss', color=color, fontsize=9)
line1 = ax1.plot(steps, loss_lora, '--', color='#94A3B8', label='Standard LoRA (r=8) Loss', lw=1.8)
line2 = ax1.plot(steps, loss_drp, '-', color=color, label='DRP-VLM Loss (Ours)', lw=2.2)
ax1.tick_params(axis='y', labelcolor=color)
ax1.set_ylim(0.2, 3.0)

ax2 = ax1.twinx()
color = '#D97706'
ax2.set_ylabel('Average Active Rank (r_eff)', color=color, fontsize=9)
line3 = ax2.plot(steps, rank_active, '-.', color=color, label='DRP-VLM Effective Rank', lw=2)
ax2.tick_params(axis='y', labelcolor=color)
ax2.set_ylim(1.0, 9.0)

lines = line1 + line2 + line3
labels = [l.get_label() for l in lines]
ax1.legend(lines, labels, loc='upper right', fontsize=7.5)

plt.title("Fig. 2: Training Convergence and Dynamic Rank Pruning Schedule", fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig('test_assets/convergence_curves.png', bbox_inches='tight')
plt.close()

# 4. Figure 3: Benchmark Comparison Bar Chart
fig, ax = plt.subplots(figsize=(5.5, 3.2), dpi=200)
methods = ['Full Tuning', 'LoRA (r=16)', 'LoRA (r=8)', 'AdaLoRA', 'DRP-VLM (Ours)']
params = [86.2, 7.08, 3.54, 2.10, 1.27] # in Millions
recall = [59.4, 58.8, 58.4, 58.9, 59.24] # MS-COCO R@1 %

x = np.arange(len(methods))
width = 0.35

rects1 = ax.bar(x - width/2, params, width, label='Trainable Params (M)', color='#64748B')
ax2 = ax.twinx()
rects2 = ax2.bar(x + width/2, recall, width, label='MS-COCO R@1 (%)', color='#0D9488')

ax.set_ylabel('Parameters (Millions, Log Scale)', fontsize=9)
ax.set_yscale('log')
ax.set_xticks(x)
ax.set_xticklabels(methods, rotation=15, ha='right', fontsize=8)
ax2.set_ylabel('Retrieval Recall@1 (%)', fontsize=9, color='#0D9488')
ax2.set_ylim(56.0, 61.0)
ax2.tick_params(axis='y', labelcolor='#0D9488')

plt.title("Fig. 3: Performance vs. Parameter Efficiency Trade-off", fontsize=10, fontweight='bold')
fig.tight_layout()
plt.savefig('test_assets/benchmark_comparison.png', bbox_inches='tight')
plt.close()

print("All test assets created successfully in test_assets/")
