namespace Marlin.FileOperations {
    public class CommonJob {
        protected unowned Gtk.Window? parent_window;
        protected uint inhibit_cookie;
        protected GLib.Cancellable? cancellable;
        protected PF.Progress.Info progress;
        protected Marlin.UndoActionData? undo_redo_data;
        protected CommonJob (Gtk.Window? parent_window = null) {
            this.parent_window = parent_window;
            inhibit_cookie = 0;
            progress = new PF.Progress.Info ();
            cancellable = progress.get_cancellable ();
            undo_redo_data = null;
        }

        ~CommonJob () {
            progress.finish ();
            uninhibit_power_manager ();
            if (undo_redo_data != null) {
                Marlin.UndoManager.instance ().add_action ((owned) undo_redo_data);
            }
        }

        protected void inhibit_power_manager (string message) {
            weak Gtk.Application app = (Gtk.Application) GLib.Application.get_default ();
            inhibit_cookie = app.inhibit (parent_window, Gtk.ApplicationInhibitFlags.LOGOUT | Gtk.ApplicationInhibitFlags.SUSPEND, message);
        }

        private void uninhibit_power_manager () {
            if (inhibit_cookie != 0) {
                return;
            }

            ((Gtk.Application) GLib.Application.get_default ()).uninhibit (inhibit_cookie);
            inhibit_cookie = 0;
        }

        protected bool aborted () {
            return cancellable.is_cancelled ();
        }
    }

    public class EmptyTrashJob : CommonJob {
        GLib.List<GLib.File> trash_dirs;

        public EmptyTrashJob (Gtk.Window? parent_window = null, owned GLib.List<GLib.File>? trash_dirs = null) {
            base (parent_window);
            if (trash_dirs != null) {
                this.trash_dirs = (owned) trash_dirs;
            } else {
                this.trash_dirs = new GLib.List<GLib.File> ();
                this.trash_dirs.prepend (GLib.File.new_for_uri ("trash:"));
            }
        }

        /* Only called if confirmation known to be required - do not second guess */
        private bool confirm_empty_trash () {
            unowned GLib.File? first_dir = trash_dirs.nth_data (0);
            if (first_dir != null) {
                unowned string primary = null;
                unowned string secondary = null;
                if (first_dir.has_uri_scheme ("trash")) {
                    /* Empty all trash */
                    primary = _("Permanently delete all items from Trash?");
                    secondary = _("All items in all trash directories, including those on any mounted external drives, will be permanently deleted.");
                } else {
                    /* Empty trash on a particular mounted volume */
                    primary = _("Permanently delete all items from Trash on this mount?");
                    secondary = _("All items in the trash on this mount, will be permanently deleted.");
                }

                var message_dialog = new Granite.MessageDialog.with_image_from_icon_name (
                    primary,
                    secondary,
                    "dialog-warning",
                    Gtk.ButtonsType.CANCEL
                );

                message_dialog.transient_for = parent_window;
                unowned Gtk.Widget empty_button = message_dialog.add_button (EMPTY_TRASH, Gtk.ResponseType.YES);
                empty_button.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                Gtk.ResponseType response = (Gtk.ResponseType) message_dialog.run ();
                message_dialog.destroy ();

                return response == Gtk.ResponseType.YES;
            }

            return true;
        }

        private async void delete_trash_file (GLib.File file, bool delete_file = true, bool delete_children = true) {
            if (aborted ()) {
                return;
            }

            if (delete_children) {
                try {
                    const string ATTRIBUTES = GLib.FileAttribute.STANDARD_NAME + "," + GLib.FileAttribute.STANDARD_TYPE;
                    var enumerator = yield file.enumerate_children_async (ATTRIBUTES, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, GLib.Priority.DEFAULT, cancellable);
                    GLib.List<GLib.FileInfo> infos;
                    while ((infos = yield enumerator.next_files_async (1, GLib.Priority.DEFAULT, cancellable)).nth_data (0) != null) {
                        foreach (unowned GLib.FileInfo info in infos) {
                            var child = file.get_child (info.get_name ());
                            yield delete_trash_file (child, true, info.get_file_type () == GLib.FileType.DIRECTORY);
                        }
                    }
                } catch (GLib.Error e) {
                    debug (e.message);
                    return;
                }
            }

            if (aborted ()) {
                return;
            }

            if (delete_file) {
                try {
                    yield file.delete_async (GLib.Priority.DEFAULT, cancellable);
                } catch (GLib.Error e) {
                    debug (e.message);
                    return;
                }
            }
        }

        public async void empty_trash () {
            inhibit_power_manager (_("Emptying Trash"));
            if (!GOF.Preferences.get_default ().confirm_trash || confirm_empty_trash ()) {
                progress.start ();
                foreach (unowned GLib.File dir in trash_dirs) {
                    if (aborted ()) {
                        break;
                    }

                    yield delete_trash_file (dir, false, true);
                }

                /* There is no job callback after emptying trash */
                Marlin.UndoManager.instance ().trash_has_emptied ();
                PF.SoundManager.get_instance ().play_empty_trash_sound ();
            }
        }
    }

    public static async bool mount_volume_full (GLib.Volume volume, Gtk.Window? parent_window = null) throws GLib.Error {
        var mount_operation = new Gtk.MountOperation (parent_window);
        mount_operation.password_save = GLib.PasswordSave.FOR_SESSION;
        try {
            yield volume.mount (GLib.MountMountFlags.NONE, mount_operation, null);
        } catch (Error e) {
            PF.Dialogs.show_error_dialog (_("Unable to mount '%s'").printf (volume.get_name ()),
                                          e.message,
                                          null);
            throw e;
        }

        return true;
    }

    public static void mount_volume (GLib.Volume volume, Gtk.Window? parent_window = null) {
        mount_volume_full.begin (volume, parent_window);
    }

    public static bool has_trash_files (GLib.Mount mount) {
        var dirs = get_trash_dirs_for_mount (mount);
        foreach (unowned GLib.File dir in dirs) {
            if (dir_has_files (dir)) {
                return true;
            }
        }

        return false;
    }

    public static GLib.List<GLib.File> get_trash_dirs_for_mount (GLib.Mount mount) {
        var list = new GLib.List<GLib.File> ();
        var root = mount.get_root ();
        if (root.is_native ()) {
            GLib.File? trash = root.resolve_relative_path (".Trash/%d");
            if (trash != null) {
                var child = trash.get_child ("files");
                if (child.query_exists ()) {
                    list.prepend (child);
                }

                child = trash.get_child ("info");
                if (child.query_exists ()) {
                    list.prepend (child);
                }
            }

            trash = root.resolve_relative_path (".Trash-%d");
            if (trash != null) {
                var child = trash.get_child ("files");
                if (child.query_exists ()) {
                    list.prepend (child);
                }

                child = trash.get_child ("info");
                if (child.query_exists ()) {
                    list.prepend (child);
                }
            }
        }

        return list;
    }

    public static void empty_trash_for_mount (Gtk.Widget? parent_view, GLib.Mount mount) {
        GLib.List<GLib.File> dirs = get_trash_dirs_for_mount (mount);
        unowned Gtk.Window? parent_window = null;
        if (parent_view != null) {
            parent_window = (Gtk.Window) parent_view.get_ancestor (typeof (Gtk.Window));
        }

        var job = new EmptyTrashJob (parent_window, (owned) dirs);
        job.empty_trash.begin ();
    }

    private static bool dir_has_files (GLib.File dir) {
        try {
            var enumerator = dir.enumerate_children (GLib.FileAttribute.STANDARD_NAME, GLib.FileQueryInfoFlags.NONE);
            if (enumerator.next_file () != null) {
                return true;
            }
        } catch (Error e) {
            return false;
        }

        return false;
    }
}
