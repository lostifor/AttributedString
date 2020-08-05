//
//  UILabelLayoutManagerDelegate.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
//  Created by Lee on 2020/8/1.
//  Copyright © 2020 LEE. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit

class UILabelLayoutManagerDelegate: NSObject, NSLayoutManagerDelegate {
    
    // 当Label发生Scalet时 最大行数为1时 基线偏移不会改变
    let scaledMetrics: UILabel.ScaledMetrics?
    
    init(_ scaledMetrics: UILabel.ScaledMetrics?) {
        self.scaledMetrics = scaledMetrics
        super.init()
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        /**
        From apple's doc:
        https://developer.apple.com/library/content/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/CustomTextProcessing/CustomTextProcessing.html
        In addition to returning the line fragment rectangle itself, the layout manager returns a rectangle called the used rectangle. This is the portion of the line fragment rectangle that actually contains glyphs or other marks to be drawn. By convention, both rectangles include the line fragment padding and the interline space (which is calculated from the font’s line height metrics and the paragraph’s line spacing parameters). However, the paragraph spacing (before and after) and any space added around the text, such as that caused by center-spaced text, are included only in the line fragment rectangle, and are not included in the used rectangle.
        */
        guard let textStorage = layoutManager.textStorage else {
            return false
        }
        guard let maximum = getMaximum(layoutManager, with: textStorage, for: glyphRange) else {
            return false
        }
        
        // 段落前间距
        var paragraphSpacingBefore: CGFloat = 0
        if glyphRange.location > 0, let paragraph = maximum.paragraph, paragraph.paragraphSpacingBefore > .ulpOfOne {
            let lastIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location - 1)
            let substring = textStorage.attributedSubstring(from: .init(location: lastIndex, length: 1)).string
            let isLineBreak = substring == "\n"
            paragraphSpacingBefore = isLineBreak ? paragraph.paragraphSpacingBefore : 0
        }
        
        // 段落间距
        var paragraphSpacing: CGFloat = 0
        if let paragraph = maximum.paragraph, paragraph.paragraphSpacing > .ulpOfOne {
            let lastIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location + glyphRange.length - 1)
            let substring = textStorage.attributedSubstring(from: .init(location: lastIndex, length: 1)).string
            let isLineBreak = substring == "\n"
            paragraphSpacing = isLineBreak ? paragraph.paragraphSpacing : 0
        }
        
        var rect = lineFragmentRect.pointee
        var used = lineFragmentUsedRect.pointee
        // 以最大的高度为准 (可解决附件问题), 同时根据最大行数是否为1来判断rect和used是否需要一致, 以解决1行数多余的行间距问题.
        let temp = max(maximum.lineHeight, used.height)
        rect.size.height = temp + maximum.lineSpacing + paragraphSpacing + paragraphSpacingBefore
        used.size.height = textContainer.maximumNumberOfLines == 1 ? temp : rect.height
        
        // 当Label发生Scaled时 最大行数为1时 基线偏移不会改变
        if let scaledMetrics = scaledMetrics, textContainer.maximumNumberOfLines == 1 {
            var baseline = baselineOffset.pointee
            let cha = CGFloat(scaledMetrics.baselineOffset - scaledMetrics.baselineOffset * scaledMetrics.actualScaleFactor)
            baseline += cha
            baselineOffset.pointee = baseline
            rect.size.height += cha
            used.size.height += cha
        }
        
        // 重新赋值最终结果
        lineFragmentRect.pointee = rect
        lineFragmentUsedRect.pointee = used
        
        /**
        From apple's doc:
        true if you modified the layout information and want your modifications to be used or false if the original layout information should be used.
        But actually returning false is also used. : )
        We should do this to solve the problem of exclusionPaths not working.
        */
        return false
    }
    
    // Implementing this method with a return value 0 will solve the problem of last line disappearing
    // when both maxNumberOfLines and lineSpacing are set, since we didn't include the lineSpacing in the lineFragmentUsedRect.
    func layoutManager(_ layoutManager: NSLayoutManager, lineSpacingAfterGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: CGRect) -> CGFloat {
        return 0
    }
}

extension UILabelLayoutManagerDelegate {
    
    private struct Maximum {
        let font: UIFont
        let lineHeight: CGFloat
        let lineSpacing: CGFloat
        let paragraph: NSParagraphStyle?
    }
    
    private func getMaximum(_ layoutManager: NSLayoutManager, with textStorage: NSTextStorage, for glyphRange: NSRange) -> Maximum? {
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        var maximumLineHeightFont: UIFont?
        var maximumLineHeight: CGFloat = 0
        var maximumLineSpacing: CGFloat = 0
        var paragraph: NSParagraphStyle?
        textStorage.enumerateAttributes(in: characterRange, options: .longestEffectiveRangeNotRequired) {
            (attributes, range, stop) in
            // 使用 NSOriginalFont 的行高进行计算 https://juejin.im/post/6844903838252531725
            guard let font = (attributes[.originalFont] ?? attributes[.font]) as? UIFont else { return }
            paragraph = paragraph ?? attributes[.paragraphStyle] as? NSParagraphStyle
            
            let lineHeight = getLineHeight(font, with: paragraph)
            // 获取最大行高
            if lineHeight > maximumLineHeight {
                maximumLineHeightFont = font
                maximumLineHeight = lineHeight
            }
            // 获取最大行间距
            if let lineSpacing = paragraph?.lineSpacing, lineSpacing > maximumLineSpacing {
                maximumLineSpacing = lineSpacing
            }
        }
        
        guard let font = maximumLineHeightFont else {
            return nil
        }
        return .init(
            font: font,
            lineHeight: maximumLineHeight,
            lineSpacing: maximumLineSpacing,
            paragraph: paragraph
        )
    }
    
    private func getLineHeight(_ font: UIFont, with paragraph: NSParagraphStyle? = .none) -> CGFloat {
        guard let paragraph = paragraph else {
            return font.lineHeight
        }
        
        var lineHeight = font.lineHeight
        
        if paragraph.lineHeightMultiple > .ulpOfOne {
            lineHeight *= paragraph.lineHeightMultiple
        }
        if paragraph.minimumLineHeight > .ulpOfOne {
            lineHeight = max(paragraph.minimumLineHeight, lineHeight)
        }
        if paragraph.maximumLineHeight > .ulpOfOne {
            lineHeight = min(paragraph.maximumLineHeight, lineHeight)
        }
        return lineHeight
    }
}

extension NSAttributedString.Key {
    
    /// 参考: https://juejin.im/post/6844903838252531725
    static let originalFont: NSAttributedString.Key = .init("NSOriginalFont")
}

#endif