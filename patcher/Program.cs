// QEWirelessFix: patches JBL QuantumENGINE's QuantumServer.dll so that the
// headset's wireless connection state (HID command 0x68) is always reported as
// "connected". Old dongle firmware always answers "not connected", which makes
// QuantumENGINE grey out every setting, including the firmware update.
//
// Usage:
//   QEWirelessFix check <QuantumServer.dll>
//   QEWirelessFix patch <QuantumServer.dll> <output.dll> [--force]
//
// Exit codes: 0 = ok, 1 = usage/IO error, 2 = already patched,
//             3 = unknown file version (use --force), 4 = unexpected file layout.

using System.Security.Cryptography;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

const string TargetType = "QEService.Feature.MiscFeature";
const string MethodName = "OnHIDPropertyChanged";

// SHA-256 of QuantumServer.dll files this patch was tested on.
var knownOriginals = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
{
    ["C6ED2A044934353ADB1819FFBBA5F25A6D37EC0D8B01CE4DBE34AF41007C6CD9"] = "QuantumENGINE 2.8.6 (QuantumServer.dll 2.0.0.5)",
};

if (args.Length < 2) return Usage();
var command = args[0].ToLowerInvariant();
var input = args[1];
if (!File.Exists(input)) return Fail(1, $"File not found: {input}");

var hash = Sha256(input);
ModuleDefMD module;
try { module = ModuleDefMD.Load(File.ReadAllBytes(input)); }
catch (Exception e) { return Fail(4, $"Not a .NET assembly or unreadable: {e.Message}"); }

var hidType = FindWirelessHidType(module);
if (hidType is null) return Fail(4, "Unexpected file layout: wireless connection class not found. Is this QuantumServer.dll?");
var alreadyPatched = hidType.Methods.Any(m => m.Name == MethodName);
var knownName = knownOriginals.TryGetValue(hash, out var n) ? n : null;

Console.WriteLine($"File:    {Path.GetFullPath(input)}");
Console.WriteLine($"SHA-256: {hash}");
Console.WriteLine($"Status:  {(alreadyPatched ? "PATCHED" : "ORIGINAL")}" + (knownName is null ? "" : $" — {knownName}"));

switch (command)
{
    case "check":
        return alreadyPatched ? 2 : 0;

    case "patch":
        if (args.Length < 3) return Usage();
        var output = args[2];
        var force = args.Skip(3).Any(a => a.Equals("--force", StringComparison.OrdinalIgnoreCase));
        if (alreadyPatched) return Fail(2, "This file is already patched. Nothing to do.");
        if (knownName is null && !force)
            return Fail(3, "This QuantumServer.dll version was not tested. Re-run with --force to patch anyway.");
        Patch(module, hidType);
        module.Write(output);
        Console.WriteLine($"Patched: {Path.GetFullPath(output)}");
        Console.WriteLine($"SHA-256: {Sha256(output)}");
        return 0;

    default:
        return Usage();
}

static TypeDef? FindWirelessHidType(ModuleDef module) =>
    module.Types.FirstOrDefault(t => t.FullName == TargetType)?
        .NestedTypes.FirstOrDefault(t => t.Name == "WirelessConnection")?
        .NestedTypes.FirstOrDefault(t => t.Name == "HIDV1");

// Adds to WirelessConnection.HIDV1:
//   protected override void OnHIDPropertyChanged(in byte value)
//   { byte connected = 1; base.OnHIDPropertyChanged(in connected); }
static void Patch(ModuleDef module, TypeDef hidType)
{
    if (hidType.BaseType is not TypeSpec { TypeSig: GenericInstSig inst } baseSpec)
        throw new InvalidOperationException("Unexpected base type of WirelessConnection.HIDV1.");
    var template = inst.GenericType.TypeDefOrRef.ResolveTypeDefThrow();
    var baseMethod = template.Methods.Single(m => m.Name == MethodName);

    // Base signature uses the generic parameter (_ValueType); the override needs the concrete type (byte).
    TypeSig Subst(TypeSig s) => s switch
    {
        GenericVar gv => inst.GenericArguments[(int)gv.Number],
        ByRefSig b => new ByRefSig(Subst(b.Next)),
        CModReqdSig r => new CModReqdSig(r.Modifier, Subst(r.Next)),
        CModOptSig o => new CModOptSig(o.Modifier, Subst(o.Next)),
        _ => s,
    };
    var baseSig = baseMethod.MethodSig;
    var overrideSig = MethodSig.CreateInstance(baseSig.RetType, baseSig.Params.Select(Subst).ToArray());
    if (overrideSig.Params.Count != 1 || Leaf(overrideSig.Params[0]).ElementType != ElementType.U1)
        throw new InvalidOperationException("Unexpected signature of OnHIDPropertyChanged (expected 'in byte').");

    var attrs = (baseMethod.Attributes & ~MethodAttributes.VtableLayoutMask) | MethodAttributes.ReuseSlot;
    var method = new MethodDefUser(MethodName, overrideSig, MethodImplAttributes.IL | MethodImplAttributes.Managed, attrs);
    foreach (var p in baseMethod.ParamDefs)
        method.ParamDefs.Add(new ParamDefUser(p.Name, p.Sequence, p.Attributes));

    var baseRef = new MemberRefUser(module, baseMethod.Name, baseSig.Clone(), baseSpec);
    var connected = new Local(module.CorLibTypes.Byte);
    var body = new CilBody { InitLocals = true };
    body.Variables.Add(connected);
    body.Instructions.Add(OpCodes.Ldc_I4_1.ToInstruction());
    body.Instructions.Add(OpCodes.Stloc.ToInstruction(connected));
    body.Instructions.Add(OpCodes.Ldarg_0.ToInstruction());
    body.Instructions.Add(OpCodes.Ldloca.ToInstruction(connected));
    body.Instructions.Add(OpCodes.Call.ToInstruction(baseRef));
    body.Instructions.Add(OpCodes.Ret.ToInstruction());
    method.Body = body;
    hidType.Methods.Add(method);
}

// Strips modifiers and by-ref wrappers: "byte& modreq(InAttribute)" -> "byte".
static TypeSig Leaf(TypeSig s)
{
    while (s is ModifierSig or ByRefSig) s = s.Next;
    return s;
}

static string Sha256(string path)
{
    using var s = File.OpenRead(path);
    return Convert.ToHexString(SHA256.HashData(s));
}

static int Fail(int code, string message)
{
    Console.Error.WriteLine("ERROR: " + message);
    return code;
}

static int Usage()
{
    Console.WriteLine("Usage:");
    Console.WriteLine("  QEWirelessFix check <QuantumServer.dll>");
    Console.WriteLine("  QEWirelessFix patch <QuantumServer.dll> <output.dll> [--force]");
    return 1;
}
