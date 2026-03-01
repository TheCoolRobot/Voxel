package core;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

/**
 * Pure-Haxe MessagePack encoder/decoder.
 * Handles all MessagePack types needed for NT4.
 */
class MsgPack {

    // ─── Decode ───────────────────────────────────────────────────────────────

    public static function decode(bytes: Bytes): Dynamic {
        var inp = new BytesInput(bytes);
        inp.bigEndian = true;
        return readValue(inp);
    }

    static function readValue(inp: BytesInput): Dynamic {
        var b = inp.readByte();

        // Positive fixint 0x00–0x7f
        if (b <= 0x7f) return b;

        // Fixmap 0x80–0x8f
        if (b >= 0x80 && b <= 0x8f) return readMap(inp, b & 0x0f);

        // Fixarray 0x90–0x9f
        if (b >= 0x90 && b <= 0x9f) return readArray(inp, b & 0x0f);

        // Fixstr 0xa0–0xbf
        if (b >= 0xa0 && b <= 0xbf) return inp.readString(b & 0x1f);

        // Negative fixint 0xe0–0xff
        if (b >= 0xe0) return b - 256;

        return switch (b) {
            case 0xc0: null;
            case 0xc2: false;
            case 0xc3: true;
            case 0xc4: readBin(inp, inp.readByte());           // bin8
            case 0xc5: readBin(inp, inp.readUInt16());          // bin16
            case 0xc6: readBin(inp, inp.readInt32());           // bin32
            case 0xca: inp.readFloat();                        // float32
            case 0xcb: inp.readDouble();                       // float64
            case 0xcc: inp.readByte();                         // uint8
            case 0xcd: inp.readUInt16();                       // uint16
            case 0xce: inp.readInt32();                        // uint32 (treat as signed)
            case 0xcf: readUInt64(inp);                        // uint64
            case 0xd0: inp.readInt8();                         // int8
            case 0xd1: inp.readInt16();                        // int16
            case 0xd2: inp.readInt32();                        // int32
            case 0xd3: inp.readInt32();                        // int64 (lower 32)
            case 0xd9: inp.readString(inp.readByte());         // str8
            case 0xda: inp.readString(inp.readUInt16());       // str16
            case 0xdb: inp.readString(inp.readInt32());        // str32
            case 0xdc: readArray(inp, inp.readUInt16());       // array16
            case 0xdd: readArray(inp, inp.readInt32());        // array32
            case 0xde: readMap(inp, inp.readUInt16());         // map16
            case 0xdf: readMap(inp, inp.readInt32());          // map32
            case _: throw 'MsgPack: unknown byte 0x${StringTools.hex(b)}';
        };
    }

    static function readArray(inp: BytesInput, len: Int): Array<Dynamic> {
        var arr = [];
        for (_ in 0...len) arr.push(readValue(inp));
        return arr;
    }

    static function readMap(inp: BytesInput, len: Int): Dynamic {
        var obj: Dynamic = {};
        for (_ in 0...len) {
            var k = readValue(inp);
            var v = readValue(inp);
            Reflect.setField(obj, Std.string(k), v);
        }
        return obj;
    }

    static function readBin(inp: BytesInput, len: Int): Bytes {
        return inp.read(len);
    }

    static function readUInt64(inp: BytesInput): Float {
        var hi = inp.readInt32();
        var lo = inp.readInt32();
        return hi * 4294967296.0 + (lo < 0 ? lo + 4294967296.0 : lo);
    }

    // ─── Encode ───────────────────────────────────────────────────────────────

    public static function encode(v: Dynamic): Bytes {
        var out = new BytesOutput();
        out.bigEndian = true;
        writeValue(out, v);
        return out.getBytes();
    }

    static function writeValue(out: BytesOutput, v: Dynamic): Void {
        if (v == null) { out.writeByte(0xc0); return; }

        if (Std.isOfType(v, Bool)) {
            out.writeByte(v ? 0xc3 : 0xc2);
            return;
        }

        if (Std.isOfType(v, Int)) {
            var i: Int = v;
            if (i >= 0 && i <= 0x7f) { out.writeByte(i); return; }
            if (i >= -32 && i < 0)   { out.writeByte(i & 0xff); return; }
            if (i >= 0 && i <= 0xff) { out.writeByte(0xcc); out.writeByte(i); return; }
            if (i >= 0 && i <= 0xffff) { out.writeByte(0xcd); out.writeUInt16(i); return; }
            out.writeByte(0xd2); out.writeInt32(i); return;
        }

        if (Std.isOfType(v, Float)) {
            out.writeByte(0xcb);
            out.writeDouble(v);
            return;
        }

        if (Std.isOfType(v, String)) {
            writeString(out, v);
            return;
        }

        if (Std.isOfType(v, Array)) {
            var arr: Array<Dynamic> = v;
            var len = arr.length;
            if (len <= 15) out.writeByte(0x90 | len);
            else if (len <= 0xffff) { out.writeByte(0xdc); out.writeUInt16(len); }
            else { out.writeByte(0xdd); out.writeInt32(len); }
            for (item in arr) writeValue(out, item);
            return;
        }

        if (Std.isOfType(v, Bytes)) {
            var b: Bytes = v;
            var len = b.length;
            if (len <= 0xff) { out.writeByte(0xc4); out.writeByte(len); }
            else if (len <= 0xffff) { out.writeByte(0xc5); out.writeUInt16(len); }
            else { out.writeByte(0xc6); out.writeInt32(len); }
            out.write(b);
            return;
        }

        // Object/map
        var fields = Reflect.fields(v);
        var len = fields.length;
        if (len <= 15) out.writeByte(0x80 | len);
        else if (len <= 0xffff) { out.writeByte(0xde); out.writeUInt16(len); }
        else { out.writeByte(0xdf); out.writeInt32(len); }
        for (f in fields) {
            writeString(out, f);
            writeValue(out, Reflect.field(v, f));
        }
    }

    static function writeString(out: BytesOutput, s: String): Void {
        var bytes = haxe.io.Bytes.ofString(s);
        var len = bytes.length;
        if (len <= 31) out.writeByte(0xa0 | len);
        else if (len <= 0xff) { out.writeByte(0xd9); out.writeByte(len); }
        else if (len <= 0xffff) { out.writeByte(0xda); out.writeUInt16(len); }
        else { out.writeByte(0xdb); out.writeInt32(len); }
        out.write(bytes);
    }
}
