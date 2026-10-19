// SPDX-License-Identifier: MPL-2.0
//! A small XML reader: just enough of XML 1.0 to read yEd's GraphML flavour.
//!
//! It builds a tiny tree of elements, decodes entity references and ignores
//! declarations, comments and processing instructions. Errors carry the line
//! and column of the offending byte.
const std = @import("std");

pub const Diagnostic = struct {
    line: usize = 1,
    column: usize = 1,
    message: []const u8 = "",
};

pub const Error = error{
    OutOfMemory,
    UnexpectedEndOfFile,
    ExpectedElement,
    MalformedTag,
    MismatchedTag,
    InvalidEntity,
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

pub const Element = struct {
    name: []const u8,
    attributes: []const Attribute,
    children: []*Element,
    text: []const u8,

    pub fn attribute(self: *const Element, name: []const u8) ?[]const u8 {
        for (self.attributes) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.value;
        }
        return null;
    }

    pub fn attributeByLocalName(self: *const Element, local: []const u8) ?[]const u8 {
        for (self.attributes) |entry| {
            if (std.mem.eql(u8, localName(entry.name), local)) return entry.value;
        }
        return null;
    }

    pub fn child(self: *const Element, local: []const u8) ?*Element {
        for (self.children) |candidate| {
            if (std.mem.eql(u8, localName(candidate.name), local)) return candidate;
        }
        return null;
    }

    pub fn firstDescendant(self: *const Element, local: []const u8) ?*Element {
        for (self.children) |candidate| {
            if (std.mem.eql(u8, localName(candidate.name), local)) return candidate;
            if (candidate.firstDescendant(local)) |found| return found;
        }
        return null;
    }

    pub fn textOrEmpty(self: *const Element) []const u8 {
        return std.mem.trim(u8, self.text, " \t\r\n");
    }
};

pub fn localName(name: []const u8) []const u8 {
    const colon = std.mem.lastIndexOfScalar(u8, name, ':') orelse return name;
    return name[colon + 1 ..];
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8, diagnostic: *Diagnostic) Error!*Element {
    var parser: Parser = .{
        .allocator = allocator,
        .source = source,
        .diagnostic = diagnostic,
    };

    while (true) {
        parser.skipWhitespace();
        if (parser.atEnd()) return parser.fail(error.UnexpectedEndOfFile, "no root element");
        if (parser.startsWith("<?") or parser.startsWith("<!--") or parser.startsWith("<!")) {
            try parser.skipPrologItem();
            continue;
        }
        break;
    }

    const root = try parser.parseElement();
    return root;
}

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    index: usize = 0,
    diagnostic: *Diagnostic,

    fn atEnd(self: *const Parser) bool {
        return self.index >= self.source.len;
    }

    fn peek(self: *const Parser) u8 {
        return self.source[self.index];
    }

    fn startsWith(self: *const Parser, text: []const u8) bool {
        return std.mem.startsWith(u8, self.source[self.index..], text);
    }

    fn fail(self: *Parser, err: Error, message: []const u8) Error {
        var line: usize = 1;
        var column: usize = 1;
        const end = @min(self.index, self.source.len);
        for (self.source[0..end]) |byte| {
            if (byte == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }
        self.diagnostic.* = .{ .line = line, .column = column, .message = message };
        return err;
    }

    fn skipWhitespace(self: *Parser) void {
        while (!self.atEnd() and std.ascii.isWhitespace(self.peek())) self.index += 1;
    }

    fn skipPrologItem(self: *Parser) Error!void {
        if (self.startsWith("<!--")) return self.skipComment();
        if (self.startsWith("<?")) return self.skipProcessingInstruction();
        return self.skipDeclaration();
    }

    fn skipComment(self: *Parser) Error!void {
        const end = std.mem.indexOfPos(u8, self.source, self.index + 4, "-->") orelse
            return self.fail(error.UnexpectedEndOfFile, "unterminated comment");
        self.index = end + 3;
    }

    fn skipProcessingInstruction(self: *Parser) Error!void {
        const end = std.mem.indexOfPos(u8, self.source, self.index + 2, "?>") orelse
            return self.fail(error.UnexpectedEndOfFile, "unterminated processing instruction");
        self.index = end + 2;
    }

    fn skipDeclaration(self: *Parser) Error!void {
        // <!DOCTYPE ...> and friends. The internal subset form is not used by
        // yEd, so a plain scan to the closing angle bracket is enough.
        const end = std.mem.indexOfScalarPos(u8, self.source, self.index + 2, '>') orelse
            return self.fail(error.UnexpectedEndOfFile, "unterminated declaration");
        self.index = end + 1;
    }

    fn parseElement(self: *Parser) Error!*Element {
        if (self.atEnd() or self.peek() != '<') {
            return self.fail(error.ExpectedElement, "expected an element");
        }
        self.index += 1;

        const name_start = self.index;
        while (!self.atEnd() and isNameByte(self.peek())) self.index += 1;
        if (self.index == name_start) return self.fail(error.MalformedTag, "element name expected");

        var element: Element = .{
            .name = self.source[name_start..self.index],
            .attributes = &.{},
            .children = &.{},
            .text = "",
        };
        try self.parseAttributes(&element);

        if (self.startsWith("/>")) {
            self.index += 2;
            return self.finish(element);
        }
        if (self.atEnd() or self.peek() != '>') return self.fail(error.MalformedTag, "expected '>'");
        self.index += 1;

        var children: std.ArrayList(*Element) = .empty;
        defer children.deinit(self.allocator);
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(self.allocator);

        while (true) {
            if (self.atEnd()) return self.fail(error.UnexpectedEndOfFile, "unclosed element");
            if (self.startsWith("</")) {
                try self.parseClosingTag(element.name);
                break;
            }
            if (self.startsWith("<!--")) {
                try self.skipComment();
                continue;
            }
            if (self.startsWith("<![CDATA[")) {
                try self.appendCdata(&text);
                continue;
            }
            if (self.startsWith("<?")) {
                try self.skipProcessingInstruction();
                continue;
            }
            if (self.startsWith("<!")) {
                try self.skipDeclaration();
                continue;
            }
            if (self.peek() == '<') {
                try children.append(self.allocator, try self.parseElement());
                continue;
            }
            try self.appendText(&text);
        }

        element.children = try children.toOwnedSlice(self.allocator);
        element.text = try text.toOwnedSlice(self.allocator);
        return self.finish(element);
    }

    fn parseClosingTag(self: *Parser, expected: []const u8) Error!void {
        self.index += 2;
        const name_start = self.index;
        while (!self.atEnd() and isNameByte(self.peek())) self.index += 1;
        const name = self.source[name_start..self.index];
        self.skipWhitespace();
        if (self.atEnd() or self.peek() != '>') return self.fail(error.MalformedTag, "expected '>'");
        self.index += 1;
        if (!std.mem.eql(u8, name, expected)) {
            return self.fail(error.MismatchedTag, "closing tag does not match the open element");
        }
    }

    fn parseAttributes(self: *Parser, element: *Element) Error!void {
        var attributes: std.ArrayList(Attribute) = .empty;
        defer attributes.deinit(self.allocator);

        while (true) {
            self.skipWhitespace();
            if (self.atEnd()) return self.fail(error.UnexpectedEndOfFile, "unterminated start tag");
            if (self.peek() == '>' or self.startsWith("/>")) break;

            const name_start = self.index;
            while (!self.atEnd() and isNameByte(self.peek())) self.index += 1;
            if (self.index == name_start) return self.fail(error.MalformedTag, "attribute name expected");
            const name = self.source[name_start..self.index];

            var value: []const u8 = "";
            self.skipWhitespace();
            if (!self.atEnd() and self.peek() == '=') {
                self.index += 1;
                self.skipWhitespace();
                if (self.atEnd()) return self.fail(error.UnexpectedEndOfFile, "attribute value expected");
                const quote = self.peek();
                if (quote != '"' and quote != '\'') {
                    return self.fail(error.MalformedTag, "quoted attribute value expected");
                }
                self.index += 1;
                const value_start = self.index;
                while (!self.atEnd() and self.peek() != quote) self.index += 1;
                if (self.atEnd()) return self.fail(error.UnexpectedEndOfFile, "unterminated attribute value");
                value = try decodeEntities(self.allocator, self.source[value_start..self.index]);
                self.index += 1;
            }

            try attributes.append(self.allocator, .{ .name = name, .value = value });
        }

        element.attributes = try attributes.toOwnedSlice(self.allocator);
    }

    fn appendText(self: *Parser, text: *std.ArrayList(u8)) Error!void {
        const start = self.index;
        while (!self.atEnd() and self.peek() != '<') self.index += 1;
        const decoded = try decodeEntities(self.allocator, self.source[start..self.index]);
        try text.appendSlice(self.allocator, decoded);
    }

    fn appendCdata(self: *Parser, text: *std.ArrayList(u8)) Error!void {
        const start = self.index + "<![CDATA[".len;
        const end = std.mem.indexOfPos(u8, self.source, start, "]]>") orelse
            return self.fail(error.UnexpectedEndOfFile, "unterminated CDATA section");
        try text.appendSlice(self.allocator, self.source[start..end]);
        self.index = end + "]]>".len;
    }

    fn finish(self: *Parser, element: Element) Error!*Element {
        const stored = try self.allocator.create(Element);
        stored.* = element;
        return stored;
    }
};

fn isNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == '.' or byte == ':' or byte >= 0x80;
}

/// Decodes the five XML entities and numeric character references. The input
/// slice is returned untouched when it contains no '&'.
pub fn decodeEntities(allocator: std.mem.Allocator, raw: []const u8) Error![]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '&') == null) return raw;

    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(allocator);

    var index: usize = 0;
    while (index < raw.len) {
        if (raw[index] != '&') {
            try decoded.append(allocator, raw[index]);
            index += 1;
            continue;
        }

        const semicolon = std.mem.indexOfScalarPos(u8, raw, index, ';') orelse return error.InvalidEntity;
        const entity = raw[index + 1 .. semicolon];
        if (entity.len == 0) return error.InvalidEntity;

        if (entity[0] == '#') {
            const code = try parseCharacterReference(entity);
            var encoded: [4]u8 = undefined;
            const length = std.unicode.utf8Encode(code, &encoded) catch return error.InvalidEntity;
            try decoded.appendSlice(allocator, encoded[0..length]);
        } else if (std.mem.eql(u8, entity, "amp")) {
            try decoded.append(allocator, '&');
        } else if (std.mem.eql(u8, entity, "lt")) {
            try decoded.append(allocator, '<');
        } else if (std.mem.eql(u8, entity, "gt")) {
            try decoded.append(allocator, '>');
        } else if (std.mem.eql(u8, entity, "quot")) {
            try decoded.append(allocator, '"');
        } else if (std.mem.eql(u8, entity, "apos")) {
            try decoded.append(allocator, '\'');
        } else {
            return error.InvalidEntity;
        }

        index = semicolon + 1;
    }

    return decoded.toOwnedSlice(allocator);
}

fn parseCharacterReference(entity: []const u8) Error!u21 {
    if (entity.len < 2) return error.InvalidEntity;
    const hexadecimal = entity[1] == 'x' or entity[1] == 'X';
    const digits = if (hexadecimal) entity[2..] else entity[1..];
    if (digits.len == 0) return error.InvalidEntity;
    const code = std.fmt.parseInt(u21, digits, if (hexadecimal) 16 else 10) catch return error.InvalidEntity;
    return code;
}

const testing = std.testing;

fn parseWithArena(arena: *std.heap.ArenaAllocator, source: []const u8, diagnostic: *Diagnostic) Error!*Element {
    return parse(arena.allocator(), source, diagnostic);
}

test "an attribute value is decoded" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostic: Diagnostic = .{};

    const root = try parseWithArena(&arena, "<a name='R&amp;D'/>", &diagnostic);

    try testing.expectEqualStrings("R&D", root.attribute("name").?);
}

test "direct text is decoded and element children do not pollute it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostic: Diagnostic = .{};

    const root = try parseWithArena(&arena, "<a>1 &lt; 2<b>inner</b></a>", &diagnostic);

    try testing.expectEqualStrings("1 < 2", root.text);
    try testing.expectEqualStrings("inner", root.child("b").?.text);
}

test "prefixes are ignored when matching local names" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostic: Diagnostic = .{};

    const root = try parseWithArena(&arena, "<y:a xmlns:y='urn:y'><y:b>text</y:b></y:a>", &diagnostic);

    try testing.expectEqualStrings("text", root.firstDescendant("b").?.text);
}

test "a self-closing element ends immediately" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostic: Diagnostic = .{};

    const root = try parseWithArena(&arena, "<a><b/><c /></a>", &diagnostic);

    try testing.expectEqual(@as(usize, 2), root.children.len);
    try testing.expectEqualStrings("", root.child("b").?.text);
}

test "comments, declarations and CDATA are handled" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostic: Diagnostic = .{};

    const root = try parseWithArena(&arena, "<?xml version='1.0'?><!-- hello --><a><![CDATA[x < y]]></a>", &diagnostic);

    try testing.expectEqualStrings("x < y", root.text);
}

test "an unclosed element names the line and column" {
    var diagnostic: Diagnostic = .{};
    try testing.expectError(error.UnexpectedEndOfFile, parse(testing.allocator, "<a>\n  <b>", &diagnostic));
    try testing.expectEqual(@as(usize, 2), diagnostic.line);
    try testing.expectEqual(@as(usize, 6), diagnostic.column);
}

test "a mismatched closing tag is rejected" {
    var diagnostic: Diagnostic = .{};
    try testing.expectError(error.MismatchedTag, parse(testing.allocator, "<a></b>", &diagnostic));
}

test "numeric character references become characters" {
    const decoded = try decodeEntities(testing.allocator, "&#65;&#x42;");
    defer testing.allocator.free(decoded);

    try testing.expectEqualStrings("AB", decoded);
}
