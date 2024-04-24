string to_one(bool x) {
	return x ? "1" : "";
}

[DBus(name = "org.freedesktop.impl.portal.Request")]
public class ScriptRequest : Object {

	private weak DBusConnection conn;
	private uint id;

	public ScriptRequest(ObjectPath h, DBusConnection conn) throws IOError {
		this.conn = conn;
		this.id = this.conn.register_object(h, this);
	}

	public void close() throws DBusError, IOError {
		this.conn.unregister_object(this.id);
	}
}

[DBus(name = "org.freedesktop.impl.portal.FileChooser")]
public class ScriptFileManager : Object {

	private const uint OK = 0;
	private const uint FAIL = 2;
	private const uint ENDED = 3;
	private DBusConnection conn;

	struct ScriptEnv {
		bool multiple;
		bool directory;
		string? path;
	}

	public ScriptFileManager(DBusConnection conn) {
		this.conn = conn;
	}

	Array<string>? launch_script(bool save, ScriptEnv env) {
		Bytes data;
		Subprocess p;

		try {
			p = new Subprocess(SubprocessFlags.STDOUT_PIPE,
					    "env",
					    "SFM_MULTIPLE=" + to_one(env.multiple),
					    "SFM_DIRECTORY=" + to_one(env.directory),
					    "SFM_SAVE=" + to_one(save),
					    "SFM_PATH=" + (env.path ?? ""),
					    "xdp-sfm", null);
			p.communicate(null, null, out data, null);
		} catch (Error e) {
			stderr.printf("setting up the script failed: %s\n", e.message);
			return null;
		}

		if (!p.get_successful()) {
			stderr.printf("failed: child exited %d\n", p.get_if_signaled() ? 127 + p.get_term_sig() : p.get_exit_status());
			return null;
		}

		stderr.printf("child successful!\n");

		Array<string> filenames = new Array<string>();
		uint8[]? content = data.get_data();
		if (content.length != 0) {
			size_t i = 0;
			for (size_t j = 0; j < content.length; j++) {
				if (content[j] == 0) {
					string chosen = (string)content[i:];
					try {
						if (filenames.length == 0 || env.multiple) {
							filenames.append_val(GLib.Filename.to_uri(chosen));
						}
					} catch (ConvertError e) {
						stderr.printf("invalid file %s (%s)\n", chosen, e.message);
					}
					i = j + 1;
				}
			}
			if (i < content.length) {
				stderr.printf("The last file in the list was not NUL-terminated\nYour script might need fixing!");
			}
		} else {
			return null;
		}
		return filenames;
	}

	ScriptEnv env_from_options(HashTable<string, Variant> opts) {
		ScriptEnv ret = { false, false, null };
		opts.for_each((k, v) => {
			if (k == "directory") {
				ret.directory = v.get_boolean();
			} else if (k == "multiple") {
				ret.multiple = v.get_boolean();
			} else if (k == "current_folder") {
				ret.path = (string)v.get_bytestring();
			} else {
				stderr.printf("ignoring key: %s\n", k);
			}
		});
		return ret;
	}

	private void open_save(
		bool save,
		ObjectPath handle,
		string app_id,
		string parent_window,
		string title,
		HashTable<string, Variant> options,
		out uint response,
		out HashTable<string, Variant> results) throws DBusError, IOError {
		/* begin */
		ScriptEnv env = env_from_options(options);
		results = new HashTable<string, Variant>(str_hash, str_equal);

		try {
			var req = new ScriptRequest(handle, this.conn);
			Array<string> choice = launch_script(save, env);

			if (choice == null || choice.length == 0) {
				response = FAIL;
			} else {
				stderr.printf("ok, writing choices\n");
				response = OK;
				results.insert("uris", choice.data);
			}
			req.close();
		} catch (Error e) {
			response = FAIL;
		}
	}

	public void open_file(
		ObjectPath h,
		string a,
		string p,
		string t,
		HashTable<string, Variant> o,
		out uint rep,
		out HashTable<string, Variant> res) throws DBusError, IOError {
		open_save(false, h, a, p, t, o, out rep, out res);
	}

	public void save_file(
		ObjectPath h,
		string a,
		string p,
		string t,
		HashTable<string, Variant> o,
		out uint rep,
		out HashTable<string, Variant> res) throws DBusError, IOError {
		open_save(true, h, a, p, t, o, out rep, out res);
	}
}

void on_bus_acquired(DBusConnection conn) {
	try {
		var service = new ScriptFileManager(conn);
		conn.register_object("/org/freedesktop/portal/desktop", service);
	} catch (IOError e) {
		stderr.printf("failed to hop on the Desktop Bus: %s\n", e.message);
	}
}

void main() {
	Bus.own_name(BusType.SESSION, "org.freedesktop.impl.portal.desktop.scriptfm",
		      BusNameOwnerFlags.NONE,
			on_bus_acquired, /* callback function on registration succeeded */
			() => {}, /* callback on name register succeeded */
			() => stderr.printf ("Could not acquire name\n"));

	new MainLoop().run();
}
