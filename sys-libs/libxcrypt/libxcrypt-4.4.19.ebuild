# Copyright 2004-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7
PYTHON_COMPAT=( python3_{7..9} )
inherit autotools multibuild python-any-r1 multilib-minimal

DESCRIPTION="Extended crypt library for descrypt, md5crypt, bcrypt, and others"
SRC_URI="https://github.com/besser82/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"
HOMEPAGE="https://github.com/besser82/libxcrypt"

LICENSE="LGPL-2.1+ public-domain BSD BSD-2"
SLOT="0/1"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~ia64 ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"
IUSE="+compat split-usr +static-libs system test"

export CTARGET=${CTARGET:-${CHOST}}
if [[ ${CTARGET} == ${CHOST} ]] ; then
	if [[ ${CATEGORY/cross-} != ${CATEGORY} ]] ; then
		export CTARGET=${CATEGORY/cross-}
	fi
fi

is_cross() { [[ ${CHOST} != ${CTARGET} ]] ; }

DEPEND="system? (
		elibc_glibc? ( sys-libs/glibc[-crypt(+)] )
		!sys-libs/musl
	)"
RDEPEND="${DEPEND}"
BDEPEND="sys-apps/findutils
	test? ( $(python_gen_any_dep 'dev-python/passlib[${PYTHON_USEDEP}]') )"

RESTRICT="!test? ( test )"

REQUIRED_USE="split-usr? ( system )"

PATCHES=(
	"${FILESDIR}/libxcrypt-4.4.19-multibuild.patch"
)

python_check_deps() {
	has_version -b "dev-python/passlib[${PYTHON_USEDEP}]"
}

pkg_setup() {
	MULTIBUILD_VARIANTS=(
		$(usex compat 'xcrypt_compat' '')
		xcrypt_nocompat
	)

	use test && python-any-r1_pkg_setup
}

src_prepare() {
	default
	eautoreconf
}

src_configure() {
	multibuild_foreach_variant multilib-minimal_src_configure
}

get_xcsysroot() {
	if is_cross; then
		echo "${EPREFIX}/usr/${CTARGET}"
	else
		echo "/"
	fi
}

get_xclibdir() {
	printf -- "%s/%s/%s/%s\n" \
		"$(get_xcsysroot)" \
		"$(usex split-usr '' '/usr')" \
		"$(get_libdir)" \
		"$(usex system '' 'xcrypt')"
}

get_xcincludedir() {
	printf -- "%s/%s/include/%s\n" \
		"$(get_xcsysroot)" \
		"$(usex split-usr '' '/usr')" \
		"$(usex system '' 'xcrypt')"
}

get_xcmandir() {
	printf -- "%s/%s/share/man\n" \
		"$(get_xcsysroot)" \
		"$(usex split-usr '' '/usr')"
}

get_xcpkgconfigdir() {
	printf -- "%s/%s/%s/pkgconfig\n" \
		"$(get_xcsysroot)" \
		"$(usex split-usr '' '/usr')" \
		"$(get_libdir)"
}

multilib_src_configure() {
	local -a myconf=(
		--disable-werror
		--with-sysroot=$(get_xcsysroot)
		--libdir=$(get_xclibdir)
		--with-pkgconfigdir=$(get_xcpkgconfigdir)
		--includedir=$(get_xcincludedir)
		--mandir="$(get_xcmandir)"
	)

	case "${MULTIBUILD_ID}" in
		xcrypt_compat-*)
			myconf+=(
				--disable-static
				--disable-xcrypt-compat-files
				--enable-obsolete-api=yes
			)
			;;
		xcrypt_nocompat-*)
			myconf+=(
				--enable-obsolete-api=no
				$(use_enable static-libs static)
			)
		;;
		*) die "Unexpected MULTIBUILD_ID: ${MULTIBUILD_ID}";;
	esac

	ECONF_SOURCE="${S}" econf "${myconf[@]}"
}

src_compile() {
	multibuild_foreach_variant multilib-minimal_src_compile
}

multilib_src_test() {
	emake check
}

src_test() {
	multibuild_foreach_variant multilib-minimal_src_test
}

src_install() {
	multibuild_foreach_variant multilib-minimal_src_install

	if ! use system; then
	(
		shopt -s failglob || die "failglob failed"

		# Make sure our man pages do not collide with glibc or man-pages.
		for manpage in "${ED}$(get_xcmandir)"/man3/crypt{,_r}.?*; do
			mv -n "${manpage}" "$(dirname "${manpage}")/xcrypt_$(basename "${manpage}")" \
				|| die "mv failed"
		done
	) || die "failglob error"
	fi

	# remove useless stuff from installation
	find "${D}"/usr/share/doc/${PF} -type l -delete || die
	find "${D}" -name '*.la' -delete || die

	# workaround broken upstream cross-* --docdir by installing files in proper locations
	if is_cross; then
		install -d ${D}$(get_xcsysroot)/usr/share/doc
		mv "${D}/usr/share/doc/${PF}" "${D}$(get_xcsysroot)/usr/share/doc/${PF}"
	fi
}

multilib_src_install() {
	emake DESTDIR="${D}" install

	# don't install the libcrypt.so symlink for the "compat" version
	case "${MULTIBUILD_ID}" in
		xcrypt_compat-*)
			rm "${D}"$(get_xclibdir)/libcrypt$(get_libname) \
				|| die "failed to remove extra compat libraries"
		;;
		xcrypt_nocompat-*)
			if use split-usr; then
				(
					if use static-libs; then
						# .a files are installed to /$(get_libdir) by default
						# move static libraries to /usr prefix or portage will abort
						shopt -s nullglob || die "failglob failed"
						static_libs=( "${ED}"/$(get_xclibdir)/*.a )

						if [[ -n ${static_libs[*]} ]]; then
							dodir "$(get_xclibdir)"
							mv "${static_libs[@]}" "${D}$(get_xclibdir)" \
								|| die "moving static libs failed"
						fi
					fi

					if use system; then
						# Move versionless .so symlinks from /$(get_libdir) to /usr/$(get_libdir)
						# to allow linker to correctly find shared libraries.
						shopt -s failglob || die "failglob failed"

						for lib_file in "${ED}"$(get_xclibdir)/*$(get_libname); do
							lib_file_basename="$(basename "${lib_file}")"
							lib_file_target="$(basename "$(readlink -f "${lib_file}")")"
							dosym "../../$(get_libdir)/${lib_file_target}" "$(get_xclibdir)/${lib_file_basename}"
						done

						rm "${ED}"$(get_xclibdir)/*$(get_libname) || die "removing symlinks in incorrect location failed"
					fi
				)
			fi
		;;
		*) die "Unexpected MULTIBUILD_ID: ${MULTIBUILD_ID}";;
	esac
}
