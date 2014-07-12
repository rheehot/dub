/**
	Compiler settings and abstraction.

	Copyright: © 2013-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.compiler;

public import dub.compilers.buildsettings;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.process;

// FIXME: Remove once separation is clear.
public import dub.compilers.buildplatform;

void warnOnSpecialCompilerFlags(string[] compiler_flags, BuildOptions options, string package_name, string config_name)
{
	struct SpecialFlag {
		string[] flags;
		string alternative;
	}
	static immutable SpecialFlag[] s_specialFlags = [
		{["-c", "-o-"], "Automatically issued by DUB, do not specify in dub.json"},
		{["-w", "-Wall", "-Werr"], `Use "buildRequirements" to control warning behavior`},
		{["-property", "-fproperty"], "Using this flag may break building of dependencies and it will probably be removed from DMD in the future"},
		{["-wi"], `Use the "buildRequirements" field to control warning behavior`},
		{["-d", "-de", "-dw"], `Use the "buildRequirements" field to control deprecation behavior`},
		{["-of"], `Use "targetPath" and "targetName" to customize the output file`},
		{["-debug", "-fdebug", "-g"], "Call dub with --build=debug"},
		{["-release", "-frelease", "-O", "-inline"], "Call dub with --build=release"},
		{["-unittest", "-funittest"], "Call dub with --build=unittest"},
		{["-lib"], `Use {"targetType": "staticLibrary"} or let dub manage this`},
		{["-D"], "Call dub with --build=docs or --build=ddox"},
		{["-X"], "Call dub with --build=ddox"},
		{["-cov"], "Call dub with --build=cov or --build=unittest-cox"},
		{["-profile"], "Call dub with --build=profile"},
		{["-version="], `Use "versions" to specify version constants in a compiler independent way`},
		{["-debug="], `Use "debugVersions" to specify version constants in a compiler independent way`},
		{["-I"], `Use "importPaths" to specify import paths in a compiler independent way`},
		{["-J"], `Use "stringImportPaths" to specify import paths in a compiler independent way`},
		{["-m32", "-m64"], `Use --arch=x86/--arch=x86_64 to specify the target architecture`}
	];

	struct SpecialOption {
		BuildOptions[] flags;
		string alternative;
	}
	static immutable SpecialOption[] s_specialOptions = [
		{[BuildOptions.debugMode], "Call DUB with --build=debug"},
		{[BuildOptions.releaseMode], "Call DUB with --build=release"},
		{[BuildOptions.coverage], "Call DUB with --build=cov or --build=unittest-cov"},
		{[BuildOptions.debugInfo], "Call DUB with --build=debug"},
		{[BuildOptions.inline], "Call DUB with --build=release"},
		{[BuildOptions.noBoundsCheck], "Call DUB with --build=release-nobounds"},
		{[BuildOptions.optimize], "Call DUB with --build=release"},
		{[BuildOptions.profile], "Call DUB with --build=profile"},
		{[BuildOptions.unittests], "Call DUB with --build=unittest"},
		{[BuildOptions.warnings, BuildOptions.warningsAsErrors], "Use \"buildRequirements\" to control the warning level"},
		{[BuildOptions.ignoreDeprecations, BuildOptions.deprecationWarnings, BuildOptions.deprecationErrors], "Use \"buildRequirements\" to control the deprecation warning level"},
		{[BuildOptions.property], "This flag is deprecated and has no effect"}
	];

	bool got_preamble = false;
	void outputPreamble()
	{
		if (got_preamble) return;
		got_preamble = true;
		logWarn("");
		if (config_name.empty) logWarn("## Warning for package %s ##", package_name);
		else logWarn("## Warning for package %s, configuration %s ##", package_name, config_name);
		logWarn("");
		logWarn("The following compiler flags have been specified in the package description");
		logWarn("file. They are handled by DUB and direct use in packages is discouraged.");
		logWarn("Alternatively, you can set the DFLAGS environment variable to pass custom flags");
		logWarn("to the compiler, or use one of the suggestions below:");
		logWarn("");
	}

	foreach (f; compiler_flags) {
		foreach (sf; s_specialFlags) {
			if (sf.flags.any!(sff => f == sff || (sff.endsWith("=") && f.startsWith(sff)))) {
				outputPreamble();
				logWarn("%s: %s", f, sf.alternative);
				break;
			}
		}
	}

	foreach (sf; s_specialOptions) {
		foreach (f; sf.flags) {
			if (options & f) {
				outputPreamble();
				logWarn("%s: %s", f, sf.alternative);
				break;
			}
		}
	}

	if (got_preamble) logWarn("");
}


/**
	Alters the build options to comply with the specified build requirements.
*/
void enforceBuildRequirements(ref BuildSettings settings)
{
	settings.addOptions(BuildOptions.warningsAsErrors);
	if (settings.requirements & BuildRequirements.allowWarnings) { settings.options &= ~BuildOptions.warningsAsErrors; settings.options |= BuildOptions.warnings; }
	if (settings.requirements & BuildRequirements.silenceWarnings) settings.options &= ~(BuildOptions.warningsAsErrors|BuildOptions.warnings);
	if (settings.requirements & BuildRequirements.disallowDeprecations) { settings.options &= ~(BuildOptions.ignoreDeprecations|BuildOptions.deprecationWarnings); settings.options |= BuildOptions.deprecationErrors; }
	if (settings.requirements & BuildRequirements.silenceDeprecations) { settings.options &= ~(BuildOptions.deprecationErrors|BuildOptions.deprecationWarnings); settings.options |= BuildOptions.ignoreDeprecations; }
	if (settings.requirements & BuildRequirements.disallowInlining) settings.options &= ~BuildOptions.inline;
	if (settings.requirements & BuildRequirements.disallowOptimization) settings.options &= ~BuildOptions.optimize;
	if (settings.requirements & BuildRequirements.requireBoundsCheck) settings.options &= ~BuildOptions.noBoundsCheck;
	if (settings.requirements & BuildRequirements.requireContracts) settings.options &= ~BuildOptions.releaseMode;
	if (settings.requirements & BuildRequirements.relaxProperties) settings.options &= ~BuildOptions.property;
}


/**
	Replaces each referenced import library by the appropriate linker flags.

	This function tries to invoke "pkg-config" if possible and falls back to
	direct flag translation if that fails.
*/
void resolveLibs(ref BuildSettings settings)
{
	import std.string : format;

	if (settings.libs.length == 0) return;

	if (settings.targetType == TargetType.library || settings.targetType == TargetType.staticLibrary) {
		logDiagnostic("Ignoring all import libraries for static library build.");
		settings.libs = null;
		version(Windows) settings.sourceFiles = settings.sourceFiles.filter!(f => !f.endsWith(".lib")).array;
	}

	version (Posix) {
		try {
			enum pkgconfig_bin = "pkg-config";
			string[] pkgconfig_libs;
			foreach (lib; settings.libs)
				if (execute([pkgconfig_bin, "--exists", "lib"~lib]).status == 0)
					pkgconfig_libs ~= lib;

			logDiagnostic("Using pkg-config to resolve library flags for %s.", pkgconfig_libs.map!(l => "lib"~l).array.join(", "));

			if (pkgconfig_libs.length) {
				auto libflags = execute([pkgconfig_bin, "--libs"] ~ pkgconfig_libs.map!(l => "lib"~l)().array());
				enforce(libflags.status == 0, format("pkg-config exited with error code %s: %s", libflags.status, libflags.output));
				foreach (f; libflags.output.split()) {
					if (f.startsWith("-Wl,")) settings.addLFlags(f[4 .. $].split(","));
					else settings.addLFlags(f);
				}
				settings.libs = settings.libs.filter!(l => !pkgconfig_libs.canFind(l)).array;
			}
			if (settings.libs.length) logDiagnostic("Using direct -l... flags for %s.", settings.libs.array.join(", "));
		} catch (Exception e) {
			logDiagnostic("pkg-config failed: %s", e.msg);
			logDiagnostic("Falling back to direct -l... flags.");
		}
	}
}

const interface Compiler {
	/// The shortest name of the compiler, lowercased. Eg: "dmd", "gdc", "ldc"
	@property string name();
	/// The path to the binary that was given as a parameter to Compiler.factory.
	/*protected*/ @property string binary();

	/// Returns an instance of a Compiler that represent the binary at path.
	/// The $PATH variable will be used, so values such as "dmd", "gdc-4.9" are accepted.
	static Compiler factory(string binPath) {
		import dub.compilers.dmd : DmdCompiler;
		import dub.compilers.gdc : GdcCompiler;
		import dub.compilers.ldc : LdcCompiler;
		if (binPath.canFind("dmd")) return new DmdCompiler(binPath);
		if (binPath.canFind("gdc")) return new GdcCompiler(binPath);
		if (binPath.canFind("ldc")) return new LdcCompiler(binPath);
		throw new Exception("Unknown compiler: "~binPath);
	}

	BuildPlatform determinePlatform(ref BuildSettings settings, string arch_override = null);

	/// Replaces high level fields with low level fields and converts
	/// dmd flags to compiler-specific flags
	void prepareBuildSettings(ref BuildSettings settings, BuildSetting supported_fields = BuildSetting.all);

	/// Removes any dflags that match one of the BuildOptions values and populates the BuildSettings.options field.
	void extractBuildOptions(ref BuildSettings settings);

	/// Adds the appropriate flag to set a target path
	void setTarget(ref BuildSettings settings, in BuildPlatform platform, string targetPath = null);

	/// Invokes the compiler using the given flags
	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback);

	/// Invokes the underlying linker directly
	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback);

	protected final void invokeTool(string[] args, void delegate(int, string) output_callback)
	{
		import std.string;

		int status;
		if (output_callback) {
			auto result = executeShell(escapeShellCommand(args));
			output_callback(result.status, result.output);
			status = result.status;
		} else {
			auto compiler_pid = spawnShell(escapeShellCommand(args));
			status = compiler_pid.wait();
		}

		version (Posix) if (status == -9) {
			throw new Exception(format("%s failed with exit code %s. This may indicate that the process has run out of memory."),
				args[0], status);
		}
		enforce(status == 0, format("%s failed with exit code %s.", args[0], status));
	}
}

string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
{
	assert(settings.targetName.length > 0, "No target name set.");
	final switch (settings.targetType) {
		case TargetType.autodetect: assert(false, "Configurations must have a concrete target type.");
		case TargetType.none: return null;
		case TargetType.sourceLibrary: return null;
		case TargetType.executable:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".exe";
			else return settings.targetName;
		case TargetType.library:
		case TargetType.staticLibrary:
			if (platform.platform.canFind("windows") && platform.compiler.name == "dmd")
				return settings.targetName ~ ".lib";
			else return "lib" ~ settings.targetName ~ ".a";
		case TargetType.dynamicLibrary:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".dll";
			else return "lib" ~ settings.targetName ~ ".so";
	}
}


bool isLinkerFile(string f)
{
	import std.path;
	switch (extension(f)) {
		default:
			return false;
		version (Windows) {
			case ".lib", ".obj", ".res", ".def":
				return true;
		} else {
			case ".a", ".o", ".so", ".dylib":
				return true;
		}
	}
}
