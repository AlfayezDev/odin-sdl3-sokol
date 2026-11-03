package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

generate_android_manifest :: proc(target: ^Target) -> string {
	if target.info.present && target.info.xml != "" do return target.info.xml
	out := strings.Builder{}
	strings.builder_init(&out)
	strings.write_string(&out, "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\"")
	props := target.info.properties

	if pk := m_get_string(props, "package"); pk != "" {
		strings.write_string(&out, " package=\"")
		strings.write_string(&out, xml_escape(pk))
		strings.write_string(&out, "\"")
	}
	strings.write_string(&out, ">\n")

	if perms, has := m_get(props, "permissions"); has {
		for perm in value_array_strings(perms) {
			strings.write_string(&out, "    <uses-permission android:name=\"")
			strings.write_string(&out, xml_escape(perm))
			strings.write_string(&out, "\" />\n")
		}
	}
	if features, has := m_get(props, "usesFeatures"); has {
		write_feature_list(&out, features)
	} else if features, has := m_get(props, "features"); has {
		write_feature_list(&out, features)
	}

	application_written := false
	if app, has := m_get(props, "application"); has {
		if am, ok := app.(Map); ok {
			write_application(&out, am)
			application_written = true
		}
	}
	if !application_written {
		strings.write_string(&out, "    <application />\n")
	}
	strings.write_string(&out, "</manifest>\n")
	return strings.to_string(out)
}

write_feature_list :: proc(out: ^strings.Builder, features: Value) {
	arr, ok := features.([]Value)
	if !ok do return
	for item in arr {
		if s, ok2 := item.(string); ok2 {
			strings.write_string(out, "    <uses-feature android:name=\"")
			strings.write_string(out, xml_escape(s))
			strings.write_string(out, "\" />\n")
		} else if m, ok2 := item.(Map); ok2 {
			strings.write_string(out, "    <uses-feature")
			write_attrs(out, m, []string{"name", "required", "version", "glEsVersion"})
			strings.write_string(out, " />\n")
		}
	}
}

write_application :: proc(out: ^strings.Builder, app: Map) {
	strings.write_string(out, "    <application")
	write_attrs(out, app, []string{"name", "label", "icon", "roundIcon", "theme", "allowBackup", "supportsRtl", "usesCleartextTraffic", "hardwareAccelerated", "extractNativeLibs", "largeHeap", "debuggable"})
	strings.write_string(out, ">\n")
	for key in app.keys {
		switch key {
		case "activities":
			write_component_list(out, app.values[key], "activity", true)
		case "services":
			write_component_list(out, app.values[key], "service", false)
		case "receivers":
			write_component_list(out, app.values[key], "receiver", false)
		case "providers":
			write_component_list(out, app.values[key], "provider", false)
		case "metaData":
			write_meta_data(out, app.values[key])
		}
	}
	strings.write_string(out, "    </application>\n")
}

write_component_list :: proc(out: ^strings.Builder, v: Value, element: string, allow_intent_filters: bool) {
	arr, ok := v.([]Value)
	if !ok do return
	for item in arr {
		if s, ok2 := item.(string); ok2 {
			strings.write_string(out, "        <")
			strings.write_string(out, element)
			strings.write_string(out, " android:name=\"")
			strings.write_string(out, xml_escape(s))
			strings.write_string(out, "\" />\n")
			continue
		}
		m, ok2 := item.(Map)
		if !ok2 do continue
		strings.write_string(out, "        <")
		strings.write_string(out, element)
		write_attrs(out, m, []string{"name", "exported", "launchMode", "theme", "label", "icon", "configChanges", "screenOrientation", "parentActivityName", "permission", "process", "authorities", "grantUriPermissions"})
		intent_filters, has_filters := m_get(m, "intentFilters")
		if allow_intent_filters && has_filters {
			strings.write_string(out, ">\n")
			write_intent_filters(out, intent_filters)
			strings.write_string(out, "        </")
			strings.write_string(out, element)
			strings.write_string(out, ">\n")
		} else {
			strings.write_string(out, " />\n")
		}
	}
}

write_intent_filters :: proc(out: ^strings.Builder, v: Value) {
	arr, ok := v.([]Value)
	if !ok do return
	for item in arr {
		m, ok2 := item.(Map)
		if !ok2 do continue
		strings.write_string(out, "            <intent-filter>\n")
		if actions, has := m_get(m, "actions"); has {
			for action in value_array_strings(actions) {
				strings.write_string(out, "                <action android:name=\"")
				strings.write_string(out, xml_escape(action))
				strings.write_string(out, "\" />\n")
			}
		}
		if categories, has := m_get(m, "categories"); has {
			for category in value_array_strings(categories) {
				strings.write_string(out, "                <category android:name=\"")
				strings.write_string(out, xml_escape(category))
				strings.write_string(out, "\" />\n")
			}
		}
		if data, has := m_get(m, "data"); has {
			if dm, ok3 := data.(Map); ok3 {
				strings.write_string(out, "                <data")
				write_attrs(out, dm, []string{"scheme", "host", "port", "path", "pathPrefix", "pathPattern", "mimeType"})
				strings.write_string(out, " />\n")
			}
		}
		strings.write_string(out, "            </intent-filter>\n")
	}
}

write_meta_data :: proc(out: ^strings.Builder, v: Value) {
	arr, ok := v.([]Value)
	if !ok do return
	for item in arr {
		m, ok2 := item.(Map)
		if !ok2 do continue
		strings.write_string(out, "        <meta-data")
		write_attrs(out, m, []string{"name", "value", "resource"})
		strings.write_string(out, " />\n")
	}
}

write_attrs :: proc(out: ^strings.Builder, m: Map, known: []string) {
	for key in m.keys {
		if key == "intentFilters" || key == "activities" || key == "services" || key == "receivers" || key == "providers" do continue
		value := m.values[key]
		if _, ok := value.(Map); ok do continue
		if _, ok := value.([]Value); ok do continue
		attr := key
		if !strings.contains(attr, ":") && string_array_contains(known, key) {
			attr = strings.concatenate([]string{"android:", attr})
		}
		strings.write_string(out, " ")
		strings.write_string(out, attr)
		strings.write_string(out, "=\"")
		strings.write_string(out, xml_escape(value_string(value)))
		strings.write_string(out, "\"")
	}
}

xml_escape :: proc(s: string) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	for c in s {
		switch c {
		case '&':
			strings.write_string(&out, "&amp;")
		case '<':
			strings.write_string(&out, "&lt;")
		case '>':
			strings.write_string(&out, "&gt;")
		case '"':
			strings.write_string(&out, "&quot;")
		case:
			strings.write_rune(&out, c)
		}
	}
	return strings.to_string(out)
}

write_target_manifest :: proc(project: ^Project, target: ^Target, module_dir: string, src_result: Source_Result) -> string {
	manifest_link := join_path(join_path(module_dir, "src/main"), "AndroidManifest.xml")
	if target.info.present && src_result.manifest_found {
		return fmt.tprintf("target %s: both info and a source AndroidManifest.xml are defined", target.name)
	}
	if target.info.present {
		xml := generate_android_manifest(target)
		path := target.info.path
		if path == "" {
			path = manifest_link
		} else if !filepath.is_abs(path) {
			path = join_path(project.base_dir, path)
		}
		parent := filepath.dir(path)
		if parent != "" do os.mkdir_all(parent)
		if err := os.write_entire_file_from_string(path, xml); err != nil {
			return fmt.tprintf("target %s: cannot write manifest: %s", target.name, path)
		}
		if clean_path(path) != clean_path(manifest_link) {
			if err := link_at(path, manifest_link); err != "" do return err
		}
		return ""
	}
	if src_result.manifest_found do return ""
	xml := generate_android_manifest(target)
	os.mkdir_all(filepath.dir(manifest_link))
	if err := os.write_entire_file_from_string(manifest_link, xml); err != nil {
		return fmt.tprintf("target %s: cannot write manifest: %s", target.name, manifest_link)
	}
	return ""
}
