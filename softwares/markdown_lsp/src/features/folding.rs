//! Folding ranges for headings (sections), lists, code blocks, block quotes,
//! tables and front matter.

use ropey::Rope;
use tower_lsp_server::ls_types::{FoldingRange, FoldingRangeKind};

use crate::analysis::{Analysis, BlockKind};
use crate::config::FoldingConfig;

/// Compute folding ranges for a document.
pub fn folding_ranges(analysis: &Analysis, rope: &Rope, config: &FoldingConfig) -> Vec<FoldingRange> {
    let mut ranges = Vec::new();
    let last_content = last_content_line(rope);

    if config.headings {
        heading_sections(analysis, last_content, &mut ranges);
    }

    for block in &analysis.blocks {
        let enabled = match block.kind {
            BlockKind::List | BlockKind::ListItem => config.lists,
            BlockKind::Code => config.code_blocks,
            BlockKind::BlockQuote => config.block_quotes,
            BlockKind::Table => config.tables,
            BlockKind::FrontMatter => config.front_matter,
        };
        if enabled && block.end_line > block.start_line {
            ranges.push(region(block.start_line, block.end_line));
        }
    }

    ranges
}

/// A heading folds from its own line down to the last line before the next
/// heading of the same or higher level (or the end of the document).
fn heading_sections(analysis: &Analysis, last_content: usize, ranges: &mut Vec<FoldingRange>) {
    let headings = &analysis.headings;
    for (i, h) in headings.iter().enumerate() {
        let mut end = last_content;
        for next in &headings[i + 1..] {
            if next.level <= h.level {
                end = next.start_line.saturating_sub(1);
                break;
            }
        }
        if end > h.start_line {
            ranges.push(region(h.start_line, end));
        }
    }
}

/// The last line index that contains non-whitespace content.
fn last_content_line(rope: &Rope) -> usize {
    let total = rope.len_lines();
    let mut last = 0;
    for i in 0..total {
        if rope.line(i).chars().any(|c| !c.is_whitespace()) {
            last = i;
        }
    }
    last
}

fn region(start_line: usize, end_line: usize) -> FoldingRange {
    FoldingRange {
        start_line: start_line as u32,
        end_line: end_line as u32,
        kind: Some(FoldingRangeKind::Region),
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analysis::analyze;

    fn folds(text: &str) -> Vec<(u32, u32)> {
        let a = analyze(text, 1);
        let rope = Rope::from_str(text);
        let mut f: Vec<(u32, u32)> = folding_ranges(&a, &rope, &FoldingConfig::default())
            .into_iter()
            .map(|r| (r.start_line, r.end_line))
            .collect();
        f.sort();
        f
    }

    #[test]
    fn nested_heading_sections() {
        let text = "\
# A
text under a

## B
text under b

# C
end";
        let f = folds(text);
        // A spans until C (line 6); B spans until blank before C.
        assert!(f.contains(&(0, 5)));
        assert!(f.contains(&(3, 5)));
    }

    #[test]
    fn code_block_folds() {
        let text = "```\nline1\nline2\n```\n";
        assert!(folds(text).contains(&(0, 3)));
    }

    #[test]
    fn list_folds() {
        let text = "- one\n- two\n- three\n";
        assert!(folds(text).contains(&(0, 2)));
    }

    #[test]
    fn respects_config_toggle() {
        let text = "```\na\nb\n```\n";
        let a = analyze(text, 1);
        let rope = Rope::from_str(text);
        let cfg = FoldingConfig {
            code_blocks: false,
            ..FoldingConfig::default()
        };
        assert!(folding_ranges(&a, &rope, &cfg).is_empty());
    }
}
