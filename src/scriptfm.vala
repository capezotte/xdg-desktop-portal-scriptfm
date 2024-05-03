string to_one(bool x) {
	return x ? "1" : "";
}

const uint OK = 0;
const uint FAIL = 2;
const uint ENDED = 3;

[DBus(name = "org.freedesktop.impl.portal.Request")]
public class ScriptRequest : Object {

	private weak DBusConnection conn;
	protected Cancellable cancellable;
	private uint id;
	private string[] argv;

	public ScriptRequest(string[] argv, ObjectPath h, DBusConnection conn) throws IOError {
		this.conn = conn;
		this.id = this.conn.register_object(h, this);
		this.cancellable = new Cancellable();
		this.argv = argv;

		this.cancellable.connect(() => {
			this.conn.unregister_object(this.id);
		});
	}

	protected async Bytes? run() throws Error {
		Bytes ret = new Bytes(null);
		bool comm = false;
		Subprocess proc;

		try {
			proc = new Subprocess.newv(this.argv, SubprocessFlags.STDOUT_PIPE);
			this.cancellable.connect(() => {
				proc.send_signal(ProcessSignal.HUP);
			});
		} catch (Error e) {
			stderr.printf("failed to create script process: %s\n", e.message);
			return null;
		}

		proc.communicate_async.begin(null, this.cancellable, (obj, res) => {
			try {
				comm = proc.communicate_async.end(res, out ret, null);
			} catch (Error e) {
				stderr.printf("script communication failed: %s\n", e.message);
				comm = false;
			} finally {
				this.conn.unregister_object(this.id);
			}
			Idle.add(this.run.callback);
		});

		yield;

		if (!comm) {
			stderr.printf("giving up: script communication failed...\n");
			return null;
		} else if (!proc.get_successful()) {
			stderr.printf("failed: child exited %d\n", proc.get_if_signaled() ? 127 + proc.get_term_sig() : proc.get_exit_status());
			return null;
		}

		stderr.printf("child successful!\n");

		return ret;
	}

	public void close() throws DBusError, IOError {
		this.cancellable.cancel();
	}
}

public class FileRequest : ScriptRequest {

	private bool multiple;

	public FileRequest(bool save, HashTable<string, Variant> opts, ObjectPath h, DBusConnection conn) throws Error {
		/* BUG: this.something segfaults until after base call */
		bool multiple = false;
		bool directory = false;
		string? path = null;


		opts.for_each((k, v) => {
			if (k == "directory") {
				directory = v.get_boolean();
			} else if (k == "multiple") {
				multiple = v.get_boolean();
			} else if (k == "current_folder") {
				path = (string)v.get_bytestring();
			} else {
				stderr.printf("ignoring key: %s\n", k);
			}
		});

		string[] args = {
			"env",
			"SFM_MULTIPLE=" + to_one(multiple),
			"SFM_DIRECTORY=" + to_one(directory),
			"SFM_SAVE=" + to_one(save),
			"SFM_PATH=" + (path ?? ""),
			Environment.get_variable("SFM_FILE_SCRIPT") ?? "xdp-sfm",
		};

		base(args, h, conn);
		this.multiple = multiple;
	}

	public new async void run(out uint rep, out HashTable<string, Variant> results) throws Error {
		results = new HashTable<string, Variant>(str_hash, str_equal);
		Bytes? data_raw = yield base.run();

		if (data_raw == null || data_raw.length <= 1) {
			rep = FAIL;
			return;
		}

		/* ensure NUL termination */
		var data = Bytes.unref_to_array(data_raw);
		if (data.data[data.data.length-1] != 0) {
			data.append({0});
		}

		Array<string> filenames = new Array<string>();
		uint8[]? content = data.data;
		size_t i = 0;
		for (size_t j = 0; j < content.length; j++) {
			if (content[j] == 0) {
				string chosen = (string)content[i:];
				try {
					if (filenames.length == 0 || this.multiple) {
						filenames.append_val(Filename.to_uri(chosen));
					}
				} catch (ConvertError e) {
					stderr.printf("invalid file %s (%s)\n", chosen, e.message);
				}
				i = j + 1;
			}
		}

		rep = OK;
		results.insert("uris", filenames.data);
	}
}

[DBus(name = "org.freedesktop.impl.portal.FileChooser")]
public class ScriptFileManager : Object {

	private DBusConnection conn;

	public ScriptFileManager(DBusConnection conn) {
		this.conn = conn;
	}

	private async void open_save(
		bool save,
		ObjectPath handle,
		HashTable<string, Variant> options,
		out uint response,
		out HashTable<string, Variant> results) throws DBusError, IOError {
		/* begin */
		FileRequest req;
		try {
			req = new FileRequest(save, options, handle, this.conn);
		} catch (Error e) {
			stderr.printf("Failed to construct file request: %s\n", e.message);
			response = FAIL;
			results = new HashTable<string, Variant>(str_hash, str_equal);
			return;
		}

		AsyncResult? outer_res = null;
		req.run.begin((obj, res) => {
			outer_res = res;
			Idle.add(open_save.callback);
		});

		yield;

		if (outer_res != null) {
			try {
				req.run.end(outer_res, out response, out results);
			} catch(Error e) {
				stderr.printf("request for file failed: %s\n", e.message);
				response = FAIL;
			}
		} else {
			response = ENDED;
			results = new HashTable<string, Variant>(str_hash, str_equal);
		}
	}

	public async void open_file(
		ObjectPath h,
		string app_id,
		string parent,
		string title,
		HashTable<string, Variant> o,
		out uint rep,
		out HashTable<string, Variant> res) throws DBusError, IOError {
		yield open_save(false, h, o, out rep, out res);
	}

	public async void save_file(
		ObjectPath h,
		string app_id,
		string parent,
		string title,
		HashTable<string, Variant> o,
		out uint rep,
		out HashTable<string, Variant> res) throws DBusError, IOError {
		yield open_save(true, h, o, out rep, out res);
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
