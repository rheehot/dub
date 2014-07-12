/**
	Build platform definitions.

	Copyright: © 2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Mathias Lang
*/
module dub.compilers.buildplatform;

import dub.compilers.compiler : Compiler;

import std.algorithm : canFind, splitter, map;
import std.array : empty, array;
import std.exception : enforce;

// FIXME: Remove me when separation is clear.
import std.typecons : Rebindable, rebindable;

/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// The Compiler to use
	Rebindable!(const Compiler) _compiler;
	/// e.g. ["posix", "windows"]
	string[] platform;
	/// e.g. ["x86", "x86_64"]
	string[] architecture;
	/// Canonical compiler name e.g. "dmd"
	string compiler;
	/// Compiled frontend version (e.g. 2065)
	int frontendVersion;
	
	enum any = BuildPlatform(rebindable!(const Compiler)(null), null, null, null, -1);
	
	/// Build platforms can be specified via a string specification.
	///
	/// Specifications are build upon the following scheme, where each component
	/// is optional (indicated by []), but the order is obligatory.
	/// "[-platform][-architecture][-compiler]"
	///
	/// So the following strings are valid specifications:
	/// "-windows-x86-dmd"
	/// "-dmd"
	/// "-arm"
	/// "-arm-dmd"
	/// "-windows-dmd"
	///
	/// Params:
	///     specification = The specification being matched. It must be the empty string or start with a dash.
	///
	/// Returns:
	///     true if the given specification matches this BuildPlatform, false otherwise. (The empty string matches)
	///
	bool matchesSpecification(const(char)[] specification)
	const {
		if (specification.empty) return true;
		if (this == any) return true;
		
		auto splitted = specification.splitter('-');
		assert(!splitted.empty, "No valid platform specification! The leading hyphen is required!");
		splitted.popFront(); // Drop leading empty match.
		enforce(!splitted.empty, "Platform specification if present, must not be empty!");
		if (platform.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
				return true;
		}
		if (architecture.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
				return true;
		}
		if (compiler == splitted.front) {
			splitted.popFront();
			enforce(splitted.empty, "No valid specification! The compiler has to be the last element!");
			return true;
		}
		return false;
	}
	unittest {
		// @@ BUG 13103 @@
		auto platform = BuildPlatform(rebindable!(const Compiler)(null), ["posix", "linux"], ["x86_64"], "dmd");
		assert(platform.matchesSpecification("-posix"));
		assert(platform.matchesSpecification("-linux"));
		assert(platform.matchesSpecification("-linux-dmd"));
		assert(platform.matchesSpecification("-linux-x86_64-dmd"));
		assert(platform.matchesSpecification("-x86_64"));
		assert(!platform.matchesSpecification("-windows"));
		assert(!platform.matchesSpecification("-ldc"));
		assert(!platform.matchesSpecification("-windows-dmd"));
	}
}

import dub.internal.vibecompat.inet.path : Path;

Path generatePlatformProbeFile()
{
	import dub.internal.vibecompat.core.file;
	import dub.internal.vibecompat.data.json;
	import dub.internal.utils;
	
	auto path = getTempDir() ~ "dub_platform_probe.d";
	
	auto fil = openFile(path, FileMode.CreateTrunc);
	scope (failure) {
		fil.close();
		removeFile(path);
	}
	
	fil.write(q{
		import std.array;
		import std.stdio;
		
		void main()
		{
			writeln(`{`);
			writefln(`  "compiler": "%s",`, determineCompiler());
			writefln(`  "frontendVersion": %s,`, __VERSION__);
			writefln(`  "compilerVendor": "%s",`, __VENDOR__);
			writefln(`  "platform": [`);
			foreach (p; determinePlatform()) writefln(`    "%s",`, p);
			writefln(`   ],`);
			writefln(`  "architecture": [`);
			foreach (p; determineArchitecture()) writefln(`    "%s",`, p);
			writefln(`   ],`);
			writeln(`}`);
		}
		
		string[] determinePlatform()
		{
			auto ret = appender!(string[])();
			version(Windows) ret.put("windows");
			version(linux) ret.put("linux");
			version(Posix) ret.put("posix");
			version(OSX) ret.put("osx");
			version(FreeBSD) ret.put("freebsd");
			version(OpenBSD) ret.put("openbsd");
			version(NetBSD) ret.put("netbsd");
			version(DragonFlyBSD) ret.put("dragonflybsd");
			version(BSD) ret.put("bsd");
			version(Solaris) ret.put("solaris");
			version(AIX) ret.put("aix");
			version(Haiku) ret.put("haiku");
			version(SkyOS) ret.put("skyos");
			version(SysV3) ret.put("sysv3");
			version(SysV4) ret.put("sysv4");
			version(Hurd) ret.put("hurd");
			version(Android) ret.put("android");
			version(Cygwin) ret.put("cygwin");
			version(MinGW) ret.put("mingw");
			return ret.data;
		}
		
		string[] determineArchitecture()
		{
			auto ret = appender!(string[])();
			version(X86) ret.put("x86");
			version(X86_64) ret.put("x86_64");
			version(ARM) ret.put("arm");
			version(ARM_Thumb) ret.put("arm_thumb");
			version(ARM_SoftFloat) ret.put("arm_softfloat");
			version(ARM_HardFloat) ret.put("arm_hardfloat");
			version(ARM64) ret.put("arm64");
			version(PPC) ret.put("ppc");
			version(PPC_SoftFP) ret.put("ppc_softfp");
			version(PPC_HardFP) ret.put("ppc_hardfp");
			version(PPC64) ret.put("ppc64");
			version(IA64) ret.put("ia64");
			version(MIPS) ret.put("mips");
			version(MIPS32) ret.put("mips32");
			version(MIPS64) ret.put("mips64");
			version(MIPS_O32) ret.put("mips_o32");
			version(MIPS_N32) ret.put("mips_n32");
			version(MIPS_O64) ret.put("mips_o64");
			version(MIPS_N64) ret.put("mips_n64");
			version(MIPS_EABI) ret.put("mips_eabi");
			version(MIPS_NoFloat) ret.put("mips_nofloat");
			version(MIPS_SoftFloat) ret.put("mips_softfloat");
			version(MIPS_HardFloat) ret.put("mips_hardfloat");
			version(SPARC) ret.put("sparc");
			version(SPARC_V8Plus) ret.put("sparc_v8plus");
			version(SPARC_SoftFP) ret.put("sparc_softfp");
			version(SPARC_HardFP) ret.put("sparc_hardfp");
			version(SPARC64) ret.put("sparc64");
			version(S390) ret.put("s390");
			version(S390X) ret.put("s390x");
			version(HPPA) ret.put("hppa");
			version(HPPA64) ret.put("hppa64");
			version(SH) ret.put("sh");
			version(SH64) ret.put("sh64");
			version(Alpha) ret.put("alpha");
			version(Alpha_SoftFP) ret.put("alpha_softfp");
			version(Alpha_HardFP) ret.put("alpha_hardfp");
			return ret.data;
		}
		
		string determineCompiler()
		{
			version(DigitalMars) return "dmd";
			else version(GNU) return "gdc";
			else version(LDC) return "ldc";
			else version(SDC) return "sdc";
			else return null;
		}
	});
	
	fil.close();
	
	return path;
}

BuildPlatform readPlatformProbe(string output)
{
	import std.string;
	
	// work around possible additional output of the compiler
	auto idx1 = output.indexOf("{");
	auto idx2 = output.lastIndexOf("}");
	enforce(idx1 >= 0 && idx1 < idx2,
	        "Unexpected platform information output - does not contain a JSON object.");
	output = output[idx1 .. idx2+1];
	
	import dub.internal.vibecompat.data.json;
	auto json = parseJsonString(output);
	
	BuildPlatform build_platform;
	build_platform.platform = json.platform.get!(Json[]).map!(e => e.get!string()).array();
	build_platform.architecture = json.architecture.get!(Json[]).map!(e => e.get!string()).array();
	build_platform.compiler = json.compiler.get!string;
	build_platform.frontendVersion = json.frontendVersion.get!int;
	return build_platform;
}
